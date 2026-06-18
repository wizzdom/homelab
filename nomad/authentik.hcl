job "authentik" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "auth.wizzdom.xyz"
  }

  group "web" {
    count = 1

    network {
      port "http" {
        to = 9000
      }
    }

    update {
      max_parallel     = 1
      health_check     = "checks"
      min_healthy_time = "10s"
      healthy_deadline = "5m"
    }

    service {
      name = "authentik"
      port = "http"

      check {
        type     = "http"
        path     = "/-/health/ready/"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "caddy.enable=true",
        "caddy.http.routers.authentik.rule=Host(`${NOMAD_META_domain}`)",

        "gatus.enable=true",
        "gatus.group=administration",
        "gatus.url=https://${NOMAD_META_domain}/-/health/ready/",
      ]
    }

    task "server" {
      driver = "docker"

      config {
        image   = "ghcr.io/goauthentik/server:2026.5"
        ports   = ["http"]
        command = "server"

        volumes = [
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/data:/data",
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/templates:/templates",
          "/etc/localtime:/etc/localtime:ro"
        ]
      }

      template {
        destination = "local/env"
        env         = true
        data        = <<EOF
AUTHENTIK_POSTGRESQL__HOST = master.postgres.service.consul
AUTHENTIK_POSTGRESQL__NAME = {{ key "authentik/db/name" }}
AUTHENTIK_POSTGRESQL__PASSWORD = {{ key "authentik/db/password" }}
AUTHENTIK_POSTGRESQL__USER = {{ key "authentik/db/user" }}
AUTHENTIK_SECRET_KEY = {{ key "authentik/secret_key" }}
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

DB_NAME="{{ key "authentik/db/name" }}"
DB_USER="{{ key "authentik/db/user" }}"
DB_PASS="{{ key "authentik/db/password" }}"
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

  group "worker" {
    count = 1

    task "worker" {
      driver = "docker"

      config {
        image   = "ghcr.io/goauthentik/server:2026.5.3"
        command = "worker"

        volumes = [
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/data:/data",
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/templates:/templates",
          "/etc/localtime:/etc/localtime:ro"
        ]
      }

      template {
        destination = "local/env"
        env         = true
        data        = <<EOF
AUTHENTIK_POSTGRESQL__HOST = master.postgres.service.consul
AUTHENTIK_POSTGRESQL__NAME = {{ key "authentik/db/name" }}
AUTHENTIK_POSTGRESQL__PASSWORD = {{ key "authentik/db/password" }}
AUTHENTIK_POSTGRESQL__USER = {{ key "authentik/db/user" }}
AUTHENTIK_SECRET_KEY = {{ key "authentik/secret_key" }}
EOF
      }

      resources {
        cpu    = 500
        memory = 1024
      }
    }
  }
}
