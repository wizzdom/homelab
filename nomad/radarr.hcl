job "radarr" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "radarr.wizzdom.xyz"
  }

  group "radarr" {
    count = 1

    network {
      port "http" {}
    }

    service {
      name = "radarr"
      port = "http"

      check {
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "caddy.enable=true",
        "caddy.http.routers.radarr.rule=Host(`${NOMAD_META_domain}`)",

        "gatus.enable=true",
        "gatus.group=media",
        "gatus.url=https://${NOMAD_META_domain}/",
      ]
    }

    task "radarr" {
      driver = "docker"

      config {
        image = "lscr.io/linuxserver/radarr:latest"
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
RADARR__APP__INSTANCENAME=radarr
RADARR__APP__THEME=dark
RADARR__AUTH__APIKEY={{ key "radarr/api/key" }}
RADARR__AUTH__METHOD=form
RADARR__AUTH__REQUIRED=true
RADARR__LOG__LEVEL=info

RADARR__POSTGRES__HOST=master.postgres.service.consul
RADARR__POSTGRES__PORT=5432
RADARR__POSTGRES__USER={{ key "radarr/db/user" }}
RADARR__POSTGRES__PASSWORD={{ key "radarr/db/password" }}
RADARR__POSTGRES__MAINDB={{ key "radarr/db/maindb/name" }}
RADARR__POSTGRES__LOGDB={{ key "radarr/db/logdb/name" }}

RADARR__SERVER__BINDADDRESS=0.0.0.0
RADARR__SERVER__PORT={{ env "NOMAD_PORT_http" }}
RADARR__SERVER__ENABLESSL=false


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

MAINDB_NAME="{{ key "radarr/db/maindb/name" }}"
LOGDB_NAME="{{ key "radarr/db/logdb/name" }}"
DB_USER="{{ key "radarr/db/user" }}"
DB_PASS="{{ key "radarr/db/password" }}"
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
