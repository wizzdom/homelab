job "tracearr" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "tracearr.wizzdom.xyz"
    docs   = "https://docs.tracearr.com/"
  }

  group "tracearr" {
    count = 1

    network {
      port "http" {}
    }

    service {
      name = "tracearr"
      port = "http"

      check {
        name     = "tracearr-http"
        type     = "http"
        path     = "/"
        port     = "http"
        interval = "10s"
        timeout  = "3s"
      }

      tags = [
        "caddy.enable=true",
        "caddy.http.routers.tracearr.rule=Host(`${NOMAD_META_domain}`)",
      ]
    }

    task "tracearr" {
      driver = "docker"

      config {
        image = "ghcr.io/connorgallopo/tracearr:latest"
        ports = ["http"]
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
NODE_ENV = production
PORT     = {{ env "NOMAD_PORT_http" }}
HOST     = 0.0.0.0
TZ       = "Europe/Dublin"

{{- range service "tracearr-db" }}
DATABASE_URL=postgres://{{ key "tracearr/db/user" }}:{{ key "tracearr/db/password" }}@{{ .Address }}:{{ .Port }}/{{ key "tracearr/db/name" }}
{{- end }}

{{- range service "tracearr-valkey" }}
REDIS_URL=redis://{{ .Address }}:{{ .Port }}
{{- end }}

GZIP_ENABLED  = true
JWT_SECRET    = {{ key "tracearr/app/secret/jwt" }}
COOKIE_SECRET = {{ key "tracearr/app/secret/cookie" }}
CORS_ORIGIN   = {{ env "NOMAD_META_domain" }}
LOG_LEVEL     = info
EOH
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }

    task "wait-for-db" {
      driver = "docker"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      config {
        image   = "alpine:3.19"
        command = "sh"
        args = [
          "-c",
          "while ! nc -z \"$DB_HOST\" \"$DB_PORT\"; do echo 'Waiting for Postgres...'; sleep 1; done; echo 'DB is ready!'"
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        change_mode = "restart"
        data        = <<EOH
{{- range service "tracearr-db" }}
DB_HOST={{ .Address }}
DB_PORT={{ .Port }}
{{- end }}
EOH
      }

      resources {
        cpu    = 50
        memory = 64
      }
    }
  }

  group "backend" {
    count = 1

    network {
      port "db" {
        to = 5432
      }

      port "valkey" {
        to = 6379
      }
    }

    service {
      name = "tracearr-db"
      port = "db"

      check {
        name     = "postgres-tcp"
        type     = "tcp"
        port     = "db"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "tsdb" {
      driver = "docker"

      config {
        image = "timescale/timescaledb-ha:pg18.1-ts2.25.0"
        ports = ["db"]

        command = "postgres"
        args = [
          "-c", "timescaledb.license=timescale",
          "-c", "timescaledb.max_tuples_decompressed_per_dml_transaction=0",
          "-c", "max_locks_per_transaction=4096",
          "-c", "timescaledb.telemetry_level=off",
        ]

        shm_size = 536870912 # 512MB

        volumes = [
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/home/postgres/pgdata/data"
        ]

        ulimit {
          nofile = "65536:65536"
        }
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
POSTGRES_NAME       = {{ key "tracearr/db/name" }}
POSTGRES_USER       = {{ key "tracearr/db/user" }}
POSTGRES_PASSWORD   = {{ key "tracearr/db/password" }}
EOH
      }

      resources {
        cpu    = 1000
        memory = 1024
      }
    }

    service {
      name = "tracearr-valkey"

      task = "valkey"
      port = "valkey"

      check {
        type     = "script"
        command  = "sh"
        args     = ["-c", "redis-cli ping || exit 1"]
        interval = "10s"
        timeout  = "2s"
      }
    }

    # Valkey cache, used as an event queue to schedule jobs
    task "valkey" {
      driver = "docker"

      config {
        image      = "valkey/valkey:9"
        force_pull = true
        ports      = ["valkey"]

        args = ["/local/valkey.conf"]
      }

      template {
        destination = "local/valkey.conf"
        data        = <<EOH
# save every 60 seconds if at least 100 keys have changed
save 60 100

dir {{ env "NOMAD_ALLOC_DIR" }}/data
EOH
      }

      resources {
        memory = 200
        cpu    = 300
      }
    }
  }
}
