job "paperless" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "paperless.wizzdom.xyz"
  }

  group "paperless-web" {
    network {
      port "http" {
        to = 8000
      }
    }

    service {
      name = "paperless"
      port = "http"

      check {
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "caddy.enable=true",
        "caddy.http.routers.paperless.rule=Host(`${NOMAD_META_domain}`)",

        "gatus.enable=true",
        "gatus.group=productivity",
        "gatus.url=https://${NOMAD_META_domain}/",
      ]
    }

    task "app" {
      driver = "docker"

      config {
        image = "ghcr.io/paperless-ngx/paperless-ngx:latest"
        ports = ["http"]

        volumes = [
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/consume:/usr/src/paperless/consume",
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/data:/usr/src/paperless/data",
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/media:/usr/src/paperless/media",
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/export:/usr/src/paperless/export",
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/preconsume:/usr/src/paperless/preconsume",
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
{{- range service "paperless-valkey" }}
PAPERLESS_REDIS             = "redis://{{ .Address }}:{{ .Port }}/0"
{{- end }}

PAPERLESS_DBENGINE          = "postgresql"
PAPERLESS_DBHOST            = "master.postgres.service.consul"
PAPERLESS_DBPORT            = "5432"
PAPERLESS_DBUSER            = "{{ key "paperless/db/user" }}"
PAPERLESS_DBNAME            = "{{ key "paperless/db/name" }}"
PAPERLESS_DBPASS            = "{{ key "paperless/db/password" }}"

PAPERLESS_SECRETKEY         = "{{ key "paperless/secret/key" }}"
PAPERLESS_URL               = "https://{{ env "NOMAD_META_domain" }}"
PAPERLESS_ALLOWED_HOSTS     = "{{- range nodes }}{{ .Address }},{{- end }}" # allow internal IPs for health check
# PAPERLESS_ALLOWED_HOSTS     = "*"
PAPERLESS_TRUSTED_PROXIES   = "172.16.0.0/12,10.0.0.0/8,192.168.0.0/16"
PAPERLESS_CONSUMER_POLLING  = 1

PAPERLESS_ADMIN_USER        = "{{ key "paperless/admin/user" }}"
PAPERLESS_ADMIN_MAIL        = "{{ key "paperless/admin/email" }}"
PAPERLESS_ADMIN_PASSWORD    = "{{ key "paperless/admin/password" }}"

PAPERLESS_EMAIL_PARSE_DEFAULT_LAYOUT=1

PAPERLESS_TIKA_ENABLED= "true"
{{- range service "tika" }}
PAPERLESS_TIKA_ENDPOINT = "http://{{ .Address }}:{{ .Port }}"
{{- end }}
{{- range service "gotenberg" }}
PAPERLESS_TIKA_GOTENBERG_ENDPOINT = "http://{{ .Address }}:{{ .Port }}"
{{- end }}

CELERY_WORKER_CONCURRENCY=2 # save my RAM
EOH
      }

      resources {
        cpu    = 800
        memory = 2048
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

DB_NAME="{{ key "paperless/db/name" }}"
DB_USER="{{ key "paperless/db/user" }}"
DB_PASS="{{ key "paperless/db/password" }}"
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

  group "broker" {

    network {
      port "valkey" {
        to = 6379
      }
    }

    service {
      name = "paperless-valkey"

      task = "valkey"
      port = "valkey"

      check {
        type     = "script"
        command  = "sh"
        args     = ["-c", "redis-cli ping || exit 1"]
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "valkey" {
      driver = "docker"

      config {
        image      = "valkey/valkey:9"
        force_pull = true
        ports      = ["valkey"]
      }

      resources {
        memory = 200
        cpu    = 300
      }
    }
  }
}
