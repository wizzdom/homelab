job "shlink" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    apidomain = "s.wizzdom.xyz"
    webdomain = "shlink.wizzdom.xyz"
    docs      = "https://shlink.io/documentation/"
  }

  group "backend" {
    count = 1

    network {
      port "api" {}
    }

    service {
      name = "shlink-api"
      port = "api"

      check {
        type     = "http"
        path     = "/rest/health"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "caddy.enable=true",
        "caddy.http.routers.shlink-api.rule=Host(`${NOMAD_META_apidomain}`)",
      ]
    }

    task "api" {
      driver = "docker"

      config {
        image = "shlinkio/shlink"
        ports = ["api"]
      }

      template {
        data        = <<EOH
DEFAULT_DOMAIN={{ env "NOMAD_META_apidomain" }}
IS_HTTPS_ENABLED=true
TIMEZONE=Europe/Dublin
TRUSTED_PROXIES=192.168.0.0/8,10.10.0.0/24,127.0.0.0/8

INITIAL_API_KEY={{ key "shlink/api/key" }}
GEOLITE_LICENSE_KEY={{ key "geolite/license/key" }}
SHELL_VERBOSITY=3
PORT={{ env "NOMAD_PORT_api" }}

DB_DRIVER=postgres
DB_USER={{ key "shlink/db/user" }}
DB_PASSWORD={{ key "shlink/db/password" }}
DB_NAME={{ key "shlink/db/name" }}
DB_HOST=master.postgres.service.consul
DB_PORT=5432

EOH
        destination = "local/file.env"
        env         = true
      }
      resources {
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

DB_NAME="{{ key "shlink/db/name" }}"
DB_USER="{{ key "shlink/db/user" }}"
DB_PASS="{{ key "shlink/db/password" }}"
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

  group "frontend" {
    count = 1

    network {
      port "web" {
        to = 8080
      }
    }

    service {
      name = "shlink-web"
      port = "web"

      check {
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "caddy.enable=true",
        "caddy.http.routers.shlink-web.rule=Host(`${NOMAD_META_webdomain}`)",
      ]
    }

    task "web" {
      driver = "docker"

      config {
        image = "shlinkio/shlink-web-client"
        ports = ["web"]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
SHLINK_SERVER_URL=https://{{ env "NOMAD_META_apidomain" }}
SHLINK_SERVER_API_KEY={{ key "shlink/api/key" }}
SHLINK_SERVER_NAME=Shlink
SHLINK_SERVER_FORWARD_CREDENTIALS=false
    EOH
      }

      resources {
        memory = 300
      }
    }
  }
}

