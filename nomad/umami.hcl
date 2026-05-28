job "umami" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "umami.wizzdom.xyz"
  }

  group "web" {
    count = 1

    network {
      port "http" {}
    }

    service {
      name = "umami"
      port = "http"

      check {
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "caddy.enable=true",
        "caddy.http.routers.umami.rule=Host(`${NOMAD_META_domain}`)",
      ]
    }

    task "umami" {
      driver = "docker"

      config {
        image = "ghcr.io/umami-software/umami:latest"
        ports = ["http"]
      }

      template {
        destination = "local/.env"
        env         = true
        change_mode = "restart"
        data        = <<EOH
DATABASE_URL  = postgresql://{{ key "umami/db/user" }}:{{ key "umami/db/password" | urlquery }}@master.postgres.service.consul:5432/{{ key "umami/db/name" }}
APP_SECRET    = {{ key "umami/app/secret" }}
HOSTNAME = "0.0.0.0"
PORT = {{ env "NOMAD_PORT_http" }}
# TODO: update the below
# GEO_DATABASE_URL = "https://example.com/GeoLite2-City.mmdb"
# IGNORE_IP = "192.168.0.1, 10.0.0.0/24, 2001:db8::/32"
# TRACKER_SCRIPT_NAME = "custom-script-name.js"
EOH
      }

      resources {
        cpu    = 50
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

DB_NAME="{{ key "umami/db/name" }}"
DB_USER="{{ key "umami/db/user" }}"
DB_PASS="{{ key "umami/db/password" }}"
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
