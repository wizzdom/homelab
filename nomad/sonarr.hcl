job "sonarr" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "sonarr.wizzdom.xyz"
  }

  group "sonarr" {
    count = 1

    network {
      port "http" {}
    }

    service {
      name = "sonarr"
      port = "http"

      tags = [
        "caddy.enable=true",
        "caddy.http.routers.sonarr.rule=Host(`${NOMAD_META_domain}`)",

        "gatus.enable=true",
        "gatus.group=media",
        "gatus.url=https://${NOMAD_META_domain}/",
      ]
    }

    task "sonarr" {
      driver = "docker"

      config {
        image = "lscr.io/linuxserver/sonarr:latest"
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
SONARR__APP__INSTANCENAME=sonarr
SONARR__APP__THEME=dark
SONARR__AUTH__APIKEY={{ key "sonarr/api/key" }}
SONARR__AUTH__METHOD=form
SONARR__AUTH__REQUIRED=true
SONARR__LOG__LEVEL=info

SONARR__POSTGRES__HOST=master.postgres.service.consul
SONARR__POSTGRES__PORT=5432
SONARR__POSTGRES__USER={{ key "sonarr/db/user" }}
SONARR__POSTGRES__PASSWORD={{ key "sonarr/db/password" }}
SONARR__POSTGRES__MAINDB={{ key "sonarr/db/maindb/name" }}
SONARR__POSTGRES__LOGDB={{ key "sonarr/db/logdb/name" }}

SONARR__SERVER__BINDADDRESS=0.0.0.0
SONARR__SERVER__PORT={{ env "NOMAD_PORT_http" }}
SONARR__SERVER__ENABLESSL=false

EOH
      }

      env {
        PUID = "1000"
        PGID = "1000"
        TZ   = "Europe/Dublin"
      }

      resources {
        cpu    = 300
        memory = 512
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

MAINDB_NAME="{{ key "sonarr/db/maindb/name" }}"
LOGDB_NAME="{{ key "sonarr/db/logdb/name" }}"
DB_USER="{{ key "sonarr/db/user" }}"
DB_PASS="{{ key "sonarr/db/password" }}"
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

echo "==> Creating databases..."
if ! $PSQL -tc "SELECT 1 FROM pg_database WHERE datname = '$MAINDB_NAME'" | grep -q 1; then
  $PSQL -c "CREATE DATABASE $MAINDB_NAME OWNER $DB_USER;"
fi
if ! $PSQL -tc "SELECT 1 FROM pg_database WHERE datname = '$LOGDB_NAME'" | grep -q 1; then
  $PSQL -c "CREATE DATABASE $LOGDB_NAME OWNER $DB_USER;"
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
