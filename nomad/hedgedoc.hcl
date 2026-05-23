job "hedgedoc" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "md.wizzdom.xyz"
  }

  group "web" {
    network {
      port "http" {}
    }

    service {
      name = "hedgedoc"
      port = "http"

      check {
        type     = "http"
        path     = "/_health"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "caddy.enable=true",
        "caddy.http.routers.md.rule=Host(`${NOMAD_META_domain}`)",
      ]
    }

    task "app" {
      driver = "docker"

      config {
        image = "quay.io/hedgedoc/hedgedoc:1.10.8"
        ports = ["http"]
      }

      template {
        destination = "secrets/.env"
        env         = true
        data        = <<EOH
CMD_DB_URL                  = "postgres://{{ key "hedgedoc/db/user" }}:{{ key "hedgedoc/db/password" }}@master.postgres.service.consul:5432/{{ key "hedgedoc/db/name" }}"

CMD_ALLOW_FREEURL           = "false"
CMD_FORBIDDEN_NOTE_IDS      = ['robots.txt', 'favicon.ico', 'api', 'build', 'css', 'docs', 'fonts', 'js', 'uploads', 'vendor', 'views', 'auth']
CMD_DOMAIN                  = "{{ env "NOMAD_META_domain" }}"
CMD_PORT                    = "{{ env "NOMAD_PORT_http" }}"
CMD_PROTOCOL_USESSL         = "true"
CMD_ALLOW_ORIGIN            = ["wizzdom.xyz"]
CMD_USE_CDN                 = "true"
CMD_PROTOCOL_USESSL         = "true"
CMD_URL_ADDPORT             = "false"
CMD_LOG_LEVEL               = "debug"
CMD_ENABLE_STATS_API        = "true"

# TODO: add accounts
# Accounts
CMD_ALLOW_EMAIL_REGISTER    = "true"
CMD_ALLOW_ANONYMOUS         = "true"
CMD_ALLOW_ANONYMOUS_EDITS   = "true"
CMD_EMAIL                   = "false"
CMD_SESSION_SECRET          = "{{ key "hedgedoc/session/secret" }}"
CMD_DEFAULT_PERMISSION      = "limited"

# Security/Privacy
CMD_HSTS_PRELOAD            = "true"
CMD_CSP_ENABLE              = "true"
CMD_HSTS_INCLUDE_SUBDOMAINS = "true"
CMD_CSP_ADD_DISQUS          = "false"
CMD_CSP_ADD_GOOGLE_ANALYTICS= "false"
CMD_CSP_ALLOW_PDF_EMBED     = "true"
CMD_ALLOW_GRAVATAR          = "true"

EOH
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

DB_NAME="{{ key "hedgedoc/db/name" }}"
DB_USER="{{ key "hedgedoc/db/user" }}"
DB_PASS="{{ key "hedgedoc/db/password" }}"
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

