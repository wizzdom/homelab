job "lldap" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "ldap.wizzdom.xyz"
  }

  group "lldap" {
    count = 1

    network {
      port "http" {
        to = 17170
      }
      port "ldap" {
        to = 3890
      }
      port "ldaps" {
        to = 6360
      }
    }

    service {
      name = "lldap-web"
      port = "http"

      check {
        type     = "http"
        path     = "/health"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "caddy.enable=true",
        "caddy.http.routers.lldap.rule=Host(`${NOMAD_META_domain}`)",
      ]
    }

    service {
      name = "lldap-ldap"
      port = "ldap"
    }

    service {
      name = "lldap-ldaps"
      port = "ldap"
    }

    task "lldap" {
      driver = "docker"

      config {
        image = "lldap/lldap:stable"
        ports = ["http", "ldap", "ldaps"]

        volumes = [
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/data:/data",
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
UID=1000
GID=1000
TZ=Europe/Dublin
LLDAP_JWT_SECRET={{ key "lldap/jwt/secret" }}
LLDAP_KEY_SEED={{ key "lldap/key/seed" }}
LLDAP_LDAP_BASE_DN={{ key "lldap/ldap/basedn" }}
LLDAP_LDAP_USER_PASS={{ key "lldap/ldap/user/pass" }}

LLDAP_LDAPS_OPTIONS__ENABLED=false
# LLDAP_LDAPS_OPTIONS__CERT_FILE=/path/to/certfile.crt
# LLDAP_LDAPS_OPTIONS__KEY_FILE=/path/to/keyfile.key

LLDAP_DATABASE_URL=postgres://{{ key "lldap/db/user" }}:{{ key "lldap/db/password" }}@master.postgres.service.consul:5432/{{ key "lldap/db/name" }}

LLDAP_SMTP_OPTIONS__ENABLE_PASSWORD_RESET=true
LLDAP_SMTP_OPTIONS__SERVER={{ key "lldap/smtp/server" }}
LLDAP_SMTP_OPTIONS__PORT={{ key "lldap/smtp/port" }}
LLDAP_SMTP_OPTIONS__SMTP_ENCRYPTION=TLS
LLDAP_SMTP_OPTIONS__USER={{ key "lldap/smtp/user" }}
LLDAP_SMTP_OPTIONS__PASSWORD={{ key "lldap/smtp/password" }}
LLDAP_SMTP_OPTIONS__FROM=no-reply accounts <{{ key "lldap/smtp/user" }}>
LLDAP_SMTP_OPTIONS__TO={{ key "lldap/smtp/reply_to" }}
EOH
      }

      restart {
        attempts = 10
        interval = "5m"
        delay    = "20s"
        mode     = "delay"
      }

      resources {
        cpu    = 1000
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

DB_NAME="{{ key "lldap/db/name" }}"
DB_USER="{{ key "lldap/db/user" }}"
DB_PASS="{{ key "lldap/db/password" }}"
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

