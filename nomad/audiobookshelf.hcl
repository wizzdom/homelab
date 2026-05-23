job "audiobookshelf" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "audiobooks.wizzdom.xyz"
  }

  group "audiobookshelf" {
    count = 1

    network {
      port "http" {}
    }

    service {
      name = "audiobookshelf"
      port = "http"

      check {
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "caddy.enable=true",
        "caddy.http.routers.audiobookshelf.rule=Host(`${NOMAD_META_domain}`)",
      ]
    }

    task "app" {
      driver = "docker"

      config {
        image = "ghcr.io/advplyr/audiobookshelf:latest"
        ports = ["http"]

        volumes = [
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/metadata:/metadata",
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/config:/config",
          "/mnt/media/audiobooks:/audiobooks",
          "/mnt/media/podcasts:/podcasts",
          "/etc/localtime:/etc/localtime:ro",
        ]
      }
      env {
        # source: https://www.audiobookshelf.org/docs/#env-configuration
        TZ   = "Europe/Dublin"
        HOST = "0.0.0.0"
        PORT = "${NOMAD_PORT_http}"
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
  }
}
