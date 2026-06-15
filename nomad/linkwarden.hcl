job "linkwarden" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "links.wizzdom.xyz"
  }

  group "web" {
    count = 1

    network {
      port "http" {
        to = 3000
      }
      port "db" {
        to = 5432
      }
    }

    service {
      name = "linkwarden"
      port = "http"

      tags = [
        "caddy.enable=true",
        "caddy.http.routers.link.rule=Host(`${NOMAD_META_domain}`)",

        "gatus.enable=true",
        "gatus.group=productivity",
        "gatus.url=https://${NOMAD_META_domain}/",
      ]
    }

    task "app" {
      driver = "docker"

      config {
        image = "ghcr.io/linkwarden/linkwarden:latest"
        ports = ["http"]

        volumes = [
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_JOB_NAME}:/data/data:rw",
        ]
      }

      resources {
        cpu    = 500
        memory = 1024
      }

      template {
        destination = "secrets/.env"
        env         = true
        data        = <<EOH
BASE_URL=https://{{ env "NOMAD_META_domain" }}/api/v1/auth
NEXTAUTH_URL=https://{{ env "NOMAD_META_domain" }}/api/v1/auth
NEXTAUTH_SECRET={{ key "linkwarden/nextauth/secret" }}

DATABASE_URL=postgresql://{{ key "linkwarden/db/user" }}:{{ key "linkwarden/db/password" }}@master.postgres.service.consul:5432/{{ key "linkwarden/db/name" }}

# Additional Optional Settings
NEXT_PUBLIC_DISABLE_REGISTRATION=false
NEXT_PUBLIC_CREDENTIALS_ENABLED=true

# MeiliSearch Settings
{{ range service "linkwarden-mellisearch" }}
MEILI_HOST={{ .Address }}:{{ .Port }}
{{- end }}
MEILI_MASTER_KEY={{ key "linkwarden/search/key" }}

# SMTP Settings
NEXT_PUBLIC_EMAIL_PROVIDER=true
EMAIL_FROM={{ key "linkwarden/smtp/from" }}
EMAIL_SERVER=smtps://{{ key "linkwarden/smtp/user" | urlquery }}:{{ key "linkwarden/smtp/password" | urlquery }}@{{ key "linkwarden/smtp/host" }}:{{ key "linkwarden/smtp/port" }}


CUSTOM_OPENAI_BASE_URL=https://openrouter.ai/api/v1
OPENAI_MODEL={{ key "linkwarden/openrouter/model" }}
OPENAI_API_KEY={{ key "linkwarden/openrouter/api/key" }}
EOH
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

DB_NAME="{{ key "linkwarden/db/name" }}"
DB_USER="{{ key "linkwarden/db/user" }}"
DB_PASS="{{ key "linkwarden/db/password" }}"
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
  group "search" {
    count = 1

    network {
      port "search" {
        to = 7700
      }
    }

    service {
      name = "linkwarden-mellisearch"
      port = "search"
    }

    task "meilisearch" {
      driver = "docker"

      config {
        image = "getmeili/meilisearch:v1.12.8"
        ports = ["search"]

        volumes = [
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/meili_data:rw",
        ]
      }

      resources {
        cpu    = 1000
        memory = 2048
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
MEILI_MASTER_KEY={{ key "linkwarden/search/key" }}
EOH
      }
    }
  }
}
