job "seerr" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "requests.wizzdom.xyz"
  }

  group "seerr" {
    count = 1

    network {
      port "http" {}
    }

    service {
      name = "seerr"
      port = "http"

      check {
        type     = "http"
        path     = "/api/v1/settings/public"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "caddy.enable=true",
        "caddy.http.routers.seerr.rule=Host(`${NOMAD_META_domain}`)",

        "gatus.enable=true",
        "gatus.group=media",
        "gatus.url=https://${NOMAD_META_domain}/",
      ]
    }

    task "seerr" {
      driver = "docker"

      config {
        image = "ghcr.io/seerr-team/seerr:latest"
        ports = ["http"]

        volumes = [
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/app/config",
          "/etc/localtime:/etc/localtime:ro",
        ]
      }

      env {
        LOG_LEVEL = "debug"
        TZ        = "Europe/Dublin"
        PORT      = "${NOMAD_PORT_http}"
      }

      template {
        destination = "secrets/seerr.env"
        env         = true
        data        = <<EOH
DB_TYPE             = "postgres"
DB_HOST             = "master.postgres.service.consul"
DB_PORT             = "5432"
DB_USER             = "{{ key "seerr/db/user" }}"
DB_PASS             = "{{ key "seerr/db/password" }}"
DB_NAME             = "{{ key "seerr/db/name" }}"
DB_POOL_SIZE        = "10"
DB_LOG_QUERIES      = "false"
EOH
      }

      resources {
        cpu    = 300
        memory = 512
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

DB_NAME="{{ key "seerr/db/name" }}"
DB_USER="{{ key "seerr/db/user" }}"
DB_PASS="{{ key "seerr/db/password" }}"
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
