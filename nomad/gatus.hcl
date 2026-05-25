job "gatus" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "status.wizzdom.xyz"
  }

  group "gatus" {
    count = 1

    network {
      port "http" {
        to = 8080
      }
    }

    service {
      name = "gatus"
      port = "http"

      tags = [
        "caddy.enable=true",
        "caddy.http.routers.gatus.rule=Host(`${NOMAD_META_domain}`)",
        # LOL
        "gatus.enable=true",
        "gatus.group=monitoring",
        "gatus.url=https://${NOMAD_META_domain}/",
      ]
    }

    task "app" {
      driver = "docker"

      config {
        image = "twinproduction/gatus:latest"
        ports = ["http"]

        volumes = [
          "/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/config",
          "local/config.yaml:/config/config.yaml",
        ]
      }

      template {
        destination = "local/config.yaml"
        change_mode = "noop"
        data        = <<EOH
ui:
  link: "https://{{ env "NOMAD_META_domain" }}"
  dark-mode: on

storage:
  type: postgres
  path: 'postgres://{{ key "gatus/db/user" | urlquery }}:{{ key "gatus/db/password" | urlquery }}@master.postgres.service.consul:5432/{{ key "gatus/db/name" }}?sslmode=disable'


endpoints:
{{- range services -}}
  {{- if .Tags | contains "gatus.enable=true" }}
  - name: {{ .Name }}
    {{- range .Tags -}}
      {{- if . | regexMatch "^gatus\\." -}}
        {{- $parts := . | split "=" -}}
        {{- $key := index $parts 0 | regexReplaceAll "^gatus\\." "" -}}
        {{- if and (eq (len $parts) 2) (ne $key "enable") }}
    {{ $key }}: {{ index $parts 1 }}
        {{- end -}}
      {{- end -}}
    {{- end }}
    interval: 60s
    conditions:
      - "[STATUS] == 200"
      - "[CERTIFICATE_EXPIRATION] > 48h"

  {{- end }}
{{- end -}}
EOH
      }

      resources {
        cpu    = 50
        memory = 64
      }
    }

    task "db-init" {
      driver = "docker"

      lifecycle {
        hook    = "prestart"
        sidecar = false # must exit 0 before main task starts
      }

      config {
        image   = "postgres:18-alpine"
        command = "/bin/sh"
        args    = ["/local/init-db.sh"]
      }

      template {
        destination = "local/init-db.sh"
        perms       = "0755"
        data        = <<EOH
#!/bin/sh
set -eu

DB_NAME="{{ key "gatus/db/name" }}"
DB_USER="{{ key "gatus/db/user" }}"
DB_PASS="{{ key "gatus/db/password" }}"
PG_SUPERUSER="{{ key "postgres/superuser/name" }}"
PGHOST="master.postgres.service.consul"
PGPORT="5432"

PSQL="psql -v ON_ERROR_STOP=1 -U $PG_SUPERUSER -h $PGHOST -p $PGPORT"

echo "==> Creating role..."
$PSQL <<EOSQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$DB_USER') THEN
    CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS';
  END IF;
END
\$\$;
EOSQL

echo "==> Creating database..."
if ! $PSQL -tc "SELECT 1 FROM pg_database WHERE datname = '$DB_NAME'" | grep -q 1; then
  $PSQL -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"
fi

echo "==> DB init done."
EOH
      }

      template {
        destination = "local/pgpass"
        perms       = "0600"
        data        = <<EOH
master.postgres.service.consul:5432:*:{{ key "postgres/superuser/name" }}:{{ key "postgres/superuser/password" }}
EOH
      }

      env {
        PGPASSFILE = "/local/pgpass"
      }

      resources {
        cpu    = 50
        memory = 64
      }
    }
  }
}
