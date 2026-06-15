job "qui" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "qui.wizzdom.xyz"
  }

  group "qui" {
    count = 1

    network {
      port "http" {
      }
    }

    service {
      name = "qui"
      port = "http"

      check {
        type     = "http"
        path     = "/health"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "caddy.enable=true",
        "caddy.http.routers.qui.rule=Host(`${NOMAD_META_domain}`)",

        "gatus.enable=true",
        "gatus.group=media",
        "gatus.url=https://${NOMAD_META_domain}/",
      ]
    }

    task "qui" {
      driver = "docker"

      config {
        image = "ghcr.io/autobrr/qui:latest"
        ports = ["http"]

        volumes = [
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/data:/config",
          "/mnt/media/torrents:/data/torrents",
        ]
      }

      env {
        PUID = "1000"
        PGID = "1000"
        TZ   = "Europe/Dublin"
      }

      template {
        destination = "secrets/.env"
        env         = true
        perms       = 400
        data        = <<EOH
QUI__HOST=0.0.0.0
QUI__PORT={{ env "NOMAD_PORT_http" }}

QUI__LOG_LEVEL=INFO      # Options: ERROR, DEBUG, INFO, WARN, TRACE

QUI__DATABASE_ENGINE=postgres
QUI__DATABASE_DSN=postgresql://{{ key "qui/db/user" }}:{{ key "qui/db/password" }}@master.postgres.service.consul:5432/{{ key "qui/db/name" }}?sslmode=disable
QUI__DATABASE_CONNECT_TIMEOUT=10
QUI__DATABASE_MAX_OPEN_CONNS=25
QUI__DATABASE_MAX_IDLE_CONNS=5
QUI__DATABASE_CONN_MAX_LIFETIME=300

QUI__CHECK_FOR_UPDATES=false
EOH
      }

      resources {
        cpu    = 150
        memory = 200
      }

      restart {
        attempts = 10
        interval = "5m"
        delay    = "20s"
        mode     = "delay"
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

DB_NAME="{{ key "qui/db/name" }}"
DB_USER="{{ key "qui/db/user" }}"
DB_PASS="{{ key "qui/db/password" }}"
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
