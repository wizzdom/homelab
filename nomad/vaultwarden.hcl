job "vaultwarden" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "vault.wizzdom.xyz"
  }

  group "vaultwarden" {
    count = 1

    network {
      port "http" {
        to = 80
      }
    }

    update {
      max_parallel     = 1
      health_check     = "checks"
      min_healthy_time = "10s"
      healthy_deadline = "5m"
    }

    service {
      name = "vaultwarden"
      port = "http"

      check {
        type     = "http"
        path     = "/alive"
        interval = "10s"
        timeout  = "2s"
      }


      tags = [
        "caddy.enable=true",
        "caddy.http.routers.vaultwarden.rule=Host(`${NOMAD_META_domain}`)",
      ]
    }

    task "app" {
      driver = "docker"

      config {
        image = "vaultwarden/server:latest-alpine"
        ports = ["http"]

        volumes = [
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/data",
          "/etc/localtime:/etc/localtime:ro"
        ]
      }

      template {
        destination = "local/env"
        env         = true
        data        = <<EOF
DOMAIN=https://{{ env "NOMAD_META_domain" }}
DATABASE_URL=postgresql://{{ key "vaultwarden/db/user" }}:{{ key "vaultwarden/db/password" }}@master.postgres.service.consul:5432/{{ key "vaultwarden/db/name" }}
SIGNUPS_ALLOWED=false
INVITATIONS_ALLOWED=true

ENABLE_WEBSOCKET=true

PUSH_ENABLED=false
PUSH_INSTALLATION_ID={{ key "vaultwarden/push/id" }}
PUSH_INSTALLATION_KEY={{ key "vaultwarden/push/key" }}

YUBICO_CLIENT_ID={{ key "vaultwarden/yubico/client_id" }}
YUBICO_SECRET_KEY={{ key "vaultwarden/yubico/secret_key" }}

# This is not the actual token, but a hash of it. Vaultwarden does not like the actual token.
ADMIN_TOKEN={{ key "vaultwarden/admin/token" }}
SMTP_HOST={{ key "vaultwarden/smtp/host" }}
SMTP_FROM={{ key "vaultwarden/smtp/from" }}
SMTP_PORT={{ key "vaultwarden/smtp/port" }}
SMTP_SECURITY=force_tls
SMTP_USERNAME={{ key "vaultwarden/smtp/username" }}
SMTP_PASSWORD={{ key "vaultwarden/smtp/password" }}
EOF
      }

      resources {
        cpu    = 500
        memory = 500
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

DB_NAME="{{ key "vaultwarden/db/name" }}"
DB_USER="{{ key "vaultwarden/db/user" }}"
DB_PASS="{{ key "vaultwarden/db/password" }}"
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
