job "qui" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "qui.wizzdom.xyz"
  }

  group "qui" {
    count = 1

    network {
      port "http" {
      }
    }

    service {
      name = "qui"
      port = "http"

      check {
        type     = "http"
        path     = "/health"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "caddy.enable=true",
        "caddy.http.routers.qui.entrypoints=web,websecure",
        "caddy.http.routers.qui.rule=Host(`${NOMAD_META_domain}`)"
      ]
    }

    task "qui" {
      driver = "docker"

      # NOTE: testing...
      template {
        destination = "secrets/image.env"
        env         = true
        change_mode = "restart"
        data        = "IMAGE_TAG={{ if nomadVarExists \"nomad/jobs/qui\" }}{{ with nomadVar \"nomad/jobs/qui\" }}{{ if .image }}{{ .image.Value }}{{ else }}latest{{ end }}{{ end }}{{ else }}latest{{ end }}"
      }

      config {
        image = "ghcr.io/autobrr/qui:${IMAGE_TAG}"
        ports = ["http"]

        volumes = [
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/data:/config",
          "/mnt/media/torrents:/data/torrents",
        ]
      }

      env {
        PUID = "1000"
        PGID = "1000"
        TZ   = "Europe/Dublin"
      }

      template {
        destination = "secrets/.env"
        env         = true
        perms       = 400
        data        = <<EOH
QUI__HOST=0.0.0.0
QUI__PORT={{ env "NOMAD_PORT_http" }}

QUI__LOG_LEVEL=INFO      # Options: ERROR, DEBUG, INFO, WARN, TRACE

# TODO: migrate to postgres
# QUI__DATABASE_ENGINE=postgres
# QUI__DATABASE_DSN=postgresql://[{{ key "qui/db/user" }}:{{ key "qui/db/password" }}@]master.postgres.service.consul:5432/{{ key "qui/db/name" }}?sslmode=disable
# QUI__DATABASE_CONNECT_TIMEOUT=10
# QUI__DATABASE_MAX_OPEN_CONNS=25
# QUI__DATABASE_MAX_IDLE_CONNS=5
# QUI__DATABASE_CONN_MAX_LIFETIME=300

QUI__CHECK_FOR_UPDATES=false
EOH
      }

      resources {
        cpu    = 150
        memory = 200
      }

      restart {
        attempts = 10
        interval = "5m"
        delay    = "20s"
        mode     = "delay"
      }
    }
  }
}
