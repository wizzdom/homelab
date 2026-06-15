job "freshrss" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "feeds.wizzdom.xyz"
  }

  group "freshrss" {
    count = 1

    network {
      port "http" {
        to = 80
      }
    }

    update {
      max_parallel     = 1
      health_check     = "checks"
      min_healthy_time = "10s"
      healthy_deadline = "5m"
    }

    service {
      name = "freshrss"
      port = "http"

      check {
        type     = "http"
        path     = "/alive"
        interval = "10s"
        timeout  = "2s"
      }


      tags = [
        "caddy.enable=true",
        "caddy.http.routers.freshrss.rule=Host(`${NOMAD_META_domain}`)",
      ]
    }

    task "app" {
      driver = "docker"

      config {
        image    = "lscr.io/linuxserver/freshrss:latest"
        hostname = "${NOMAD_META_domain}"
        ports    = ["http"]

        volumes = [
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/config",
          "/etc/localtime:/etc/localtime:ro"
        ]
      }

      template {
        destination = "local/env"
        env         = true
        data        = <<EOH
FRESHRSS_INSTALL=--api-enabled --base-url {{ env "NOMAD_META_domain" }} --db-base {{ key "freshrss/db/name" }} --db-host master.postgres.service.consul:5432 --db-password {{ key "freshrss/db/password" }} --db-type pgsql --db-user {{ key "freshrss/db/user" }} --default-user admin --language en
FRESHRSS_USER=--api-password {{ key "freshrss/api/password" }} --email {{ key "freshrss/admin/email" }} --language en --password {{ key "freshrss/admin/password" }} --user {{ key "freshrss/admin/user" }}
EOH
      }

      resources {
        cpu    = 500
        memory = 256
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

DB_NAME="{{ key "freshrss/db/name" }}"
DB_USER="{{ key "freshrss/db/user" }}"
DB_PASS="{{ key "freshrss/db/password" }}"
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
