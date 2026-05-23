job "prowlarr" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "prowlarr.wizzdom.xyz"
  }

  group "prowlarr" {
    count = 1

    network {
      port "http" {}
    }

    service {
      name = "prowlarr"
      port = "http"

      check {
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "caddy.enable=true",
        "caddy.http.routers.prowl.rule=Host(`${NOMAD_META_domain}`)",
      ]
    }

    task "prowlarr" {
      driver = "docker"

      config {
        image = "lscr.io/linuxserver/prowlarr:latest"
        ports = ["http"]

        volumes = [
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/data:/config",
          "/etc/localtime:/etc/localtime:ro",
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
prowlarr__APP__INSTANCENAME=prowlarr
prowlarr__APP__THEME=dark
prowlarr__AUTH__APIKEY={{ key "prowlarr/api/key" }}
prowlarr__AUTH__METHOD=form
prowlarr__AUTH__REQUIRED=true
prowlarr__LOG__LEVEL=info

prowlarr__POSTGRES__HOST=master.postgres.service.consul
prowlarr__POSTGRES__PORT=5432
prowlarr__POSTGRES__USER={{ key "prowlarr/db/user" }}
prowlarr__POSTGRES__PASSWORD={{ key "prowlarr/db/password" }}
prowlarr__POSTGRES__MAINDB={{ key "prowlarr/db/maindb/name" }}
prowlarr__POSTGRES__LOGDB={{ key "prowlarr/db/logdb/name" }}

prowlarr__SERVER__BINDADDRESS=0.0.0.0
prowlarr__SERVER__PORT={{ env "NOMAD_PORT_http" }}
prowlarr__SERVER__ENABLESSL=false


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

MAINDB_NAME="{{ key "prowlarr/db/maindb/name" }}"
LOGDB_NAME="{{ key "prowlarr/db/logdb/name" }}"
DB_USER="{{ key "prowlarr/db/user" }}"
DB_PASS="{{ key "prowlarr/db/password" }}"
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
