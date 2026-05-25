job "netronome" {
  datacenters = ["dc1"]
  type        = "service"

  constraint {
    attribute = "${attr.unique.hostname}"
    value     = "morpheus"
  }

  meta {
    domain = "netronome.wizzdom.xyz"
  }

  group "netronome" {
    count = 1

    network {
      port "http" {
        to = 7575
      }
    }

    service {
      name = "netronome"
      port = "http"

      check {
        type     = "http"
        path     = "/health"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "caddy.enable=true",
        "caddy.http.routers.netronome.rule=Host(`${NOMAD_META_domain}`)",
      ]
    }

    task "netronome" {
      driver = "docker"

      config {
        image   = "ghcr.io/autobrr/netronome:latest"
        ports   = ["http"]
        cap_add = ["NET_RAW"] # needed to get proper host network speed

        volumes = [
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/data:/config",
          "/etc/localtime:/etc/localtime:ro",
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOF
NETRONOME__HOST=0.0.0.0
NETRONOME__PORT={{ env "NOMAD_PORT_http" }}

NETRONOME__DB_TYPE      = postgres
NETRONOME__DB_HOST      = master.postgres.service.consul
NETRONOME__DB_PORT      = 5432
NETRONOME__DB_USER      = {{ key "netronome/db/user" }}
NETRONOME__DB_PASSWORD  = {{ key "netronome/db/password" }}
NETRONOME__DB_NAME      = {{ key "netronome/db/name" }}
NETRONOME__DB_SSLMODE   = disable

NETRONOME__OIDC_ISSUER=                      # OIDC provider URL
NETRONOME__OIDC_CLIENT_ID=                   # OIDC client ID
NETRONOME__OIDC_CLIENT_SECRET=               # OIDC client secret
NETRONOME__OIDC_REDIRECT_URL=                # OIDC callback URL

NETRONOME__SPEEDTEST_TIMEOUT=30              # Overall speedtest timeout (seconds)
EOF
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

DB_NAME="{{ key "netronome/db/name" }}"
DB_USER="{{ key "netronome/db/user" }}"
DB_PASS="{{ key "netronome/db/password" }}"
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
