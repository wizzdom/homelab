job "bazarr" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "bazarr.wizzdom.xyz"
  }

  group "bazarr" {
    count = 1

    network {
      port "http" {
        to = 6767
      }
    }

    service {
      name = "bazarr"
      port = "http"

      check {
        type     = "http"
        path     = "/health"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "caddy.enable=true",
        "caddy.http.routers.bazarr.rule=Host(`${NOMAD_META_domain}`)",

        "gatus.enable=true",
        "gatus.group=media",
        "gatus.url=https://${NOMAD_META_domain}/health",
      ]
    }

    task "bazarr" {
      driver = "docker"

      config {
        image = "lscr.io/linuxserver/bazarr:development"
        ports = ["http"]

        volumes = [
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/data:/config",
          "/mnt/media:/data",
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
PUID                = "1000"
PGID                = "1000"
TZ                  = "Europe/Dublin"

POSTGRES_ENABLED    = "true"
POSTGRES_DATABASE   = "{{ key "bazarr/db/name" }}"
POSTGRES_USERNAME   = "{{ key "bazarr/db/user" }}"
POSTGRES_PASSWORD   = "{{ key "bazarr/db/password" }}"
POSTGRES_HOST       = "master.postgres.service.consul"
POSTGRES_PORT       = "5432"
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

DB_NAME="{{ key "bazarr/db/name" }}"
DB_USER="{{ key "bazarr/db/user" }}"
DB_PASS="{{ key "bazarr/db/password" }}"
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
