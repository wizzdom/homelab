job "sure" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "sure.wizzdom.xyz"
  }

  group "web" {
    count = 1

    network {
      port "http" {}
    }

    update {
      max_parallel     = 1
      health_check     = "checks"
      min_healthy_time = "10s"
      healthy_deadline = "5m"
    }

    service {
      name = "sure"
      port = "http"

      # check {
      #   type     = "http"
      #   path     = "/"
      #   interval = "10s"
      #   timeout  = "2s"
      # }


      tags = [
        "caddy.enable=true",
        "caddy.http.routers.sure.rule=Host(`${NOMAD_META_domain}`)",
        #
        # "gatus.enable=true",
        # "gatus.group=productivity",
        # "gatus.url=https://${NOMAD_META_domain}/",
      ]
    }

    task "app" {
      driver = "docker"

      config {
        image = "ghcr.io/we-promise/sure:stable"
        ports = ["http"]

        volumes = [
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/rails/storage",
          "/etc/localtime:/etc/localtime:ro"
        ]
      }

      template {
        destination = "local/env"
        env         = true
        data        = <<EOF
PORT = {{ env "NOMAD_PORT_http" }}
ONBOARDING_STATE=closed

APP_DOMAIN={{ env "NOMAD_META_domain" }}

SECRET_KEY_BASE = {{ key "sure/secret_key/base" }}
SELF_HOSTED = "true"
RAILS_FORCE_SSL = "false"
RAILS_ASSUME_SSL = "true"

WEBAUTHN_RP_ID="{{ env "NOMAD_META_domain" }}"
WEBAUTHN_ALLOWED_ORIGINS="https://{{ env "NOMAD_META_domain" }}"

DB_HOST = "master.postgres.service.consul"
DB_PORT = 5432
POSTGRES_USER = {{ key "sure/db/user" }}
POSTGRES_PASSWORD = {{ key "sure/db/password" }}
POSTGRES_DB = {{ key "sure/db/name" }}

{{- range service "sure-valkey" }}
REDIS_URL=redis://{{ .Address }}:{{ .Port }}/1
{{- end }}
# NOTE: enabling OpenAI will incur costs when you use AI-related features in the app (chat, rules).  Make sure you have set appropriate spend limits on your account before adding this.
# OPENAI_ACCESS_TOKEN = ""
EOF
      }

      resources {
        cpu    = 500
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

DB_NAME="{{ key "sure/db/name" }}"
DB_USER="{{ key "sure/db/user" }}"
DB_PASS="{{ key "sure/db/password" }}"
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
  group "worker" {
    count = 1

    task "worker" {
      driver = "docker"

      config {
        image   = "ghcr.io/we-promise/sure:stable"
        command = "bundle"
        args    = ["exec", "sidekiq"]

        volumes = [
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/rails/storage",
          "/etc/localtime:/etc/localtime:ro"
        ]
      }

      template {
        destination = "local/env"
        env         = true
        data        = <<EOF
PORT = {{ env "NOMAD_PORT_http" }}
ONBOARDING_STATE=closed

APP_DOMAIN={{ env "NOMAD_META_domain" }}

SECRET_KEY_BASE = {{ key "sure/secret_key/base" }}
SELF_HOSTED = "true"
RAILS_FORCE_SSL = "false"
RAILS_ASSUME_SSL = "true"

WEBAUTHN_RP_ID="{{ env "NOMAD_META_domain" }}"
WEBAUTHN_ALLOWED_ORIGINS="https://{{ env "NOMAD_META_domain" }}"

DB_HOST = "master.postgres.service.consul"
DB_PORT = 5432
POSTGRES_USER = {{ key "sure/db/user" }}
POSTGRES_PASSWORD = {{ key "sure/db/password" }}
POSTGRES_DB = {{ key "sure/db/name" }}

{{- range service "sure-valkey" }}
REDIS_URL=redis://{{ .Address }}:{{ .Port }}/1
{{- end }}
# NOTE: enabling OpenAI will incur costs when you use AI-related features in the app (chat, rules).  Make sure you have set appropriate spend limits on your account before adding this.
# OPENAI_ACCESS_TOKEN = ""
EOF
      }

      resources {
        cpu    = 500
        memory = 1024
      }
    }
  }

  group "valkey" {
    count = 1

    network {
      port "valkey" {
        to = 6379
      }
    }

    service {
      name = "sure-valkey"

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

        args = ["/local/valkey.conf"]
      }

      template {
        destination = "local/valkey.conf"
        data        = <<EOH
# save every 60 seconds if at least 100 keys have changed
save 60 100

dir {{ env "NOMAD_ALLOC_DIR" }}/data
EOH
      }

      resources {
        memory = 200
        cpu    = 300
      }
    }
  }
}
