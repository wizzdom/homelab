job "home-assistant" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "ha.wizzdom.xyz"
  }

  group "home-assistant" {
    count = 1

    network {
      port "http" {
        to = 8123
      }
    }

    service {
      name = "home-assistant"
      port = "http"

      check {
        type     = "http"
        path     = "/" # no healthcheck endpoint, expecting a HTTP 405
        interval = "60s"
        timeout  = "2s"
      }

      tags = [
        "caddy.enable=true",
        "caddy.http.routers.ha.rule=Host(`${NOMAD_META_domain}`)",
      ]
    }

    task "home-assistant" {
      driver = "docker"

      config {
        image = "ghcr.io/home-assistant/home-assistant:stable"
        ports = ["http"]

        volumes = [
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/config:/config:rw",
          "local/configuration.yaml:/config/configuration.yaml:ro",
          "/etc/localtime:/etc/localtime:ro",
          "/run/dbus:/run/dbus:ro",
        ]
      }

      template {
        destination = "local/configuration.yaml"
        change_mode = "restart"
        data        = <<EOF
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 172.16.0.0/12
    - 10.0.0.0/8
    - 192.168.0.0/16

recorder:
db_url: postgresql://{{ key "home-assistant/db/user"}}:{{ key "home-assistant/db/password"}}@master.postgres.service.consul:5432/{{ key "home-assistant/db/name" }}

# Loads default set of integrations. Do not remove.
default_config:

# Load frontend themes from the themes folder
frontend:
  themes: !include_dir_merge_named themes

automation: !include automations.yaml
script: !include scripts.yaml
scene: !include scenes.yaml
EOF
      }

      resources {
        cpu    = 500
        memory = 1024
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

DB_NAME="{{ key "home-assistant/db/name" }}"
DB_USER="{{ key "home-assistant/db/user" }}"
DB_PASS="{{ key "home-assistant/db/password" }}"
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
