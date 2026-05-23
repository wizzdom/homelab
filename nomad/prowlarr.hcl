job "prowlarr" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "prowlarr.wizzdom.xyz"
  }

  group "prowlarr" {
    count = 1

    network {
      port "http" {}
    }

    service {
      name = "prowlarr"
      port = "http"

      check {
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "caddy.enable=true",
        "caddy.http.routers.prowl.rule=Host(`${NOMAD_META_domain}`)",
      ]
    }

    task "prowlarr" {
      driver = "docker"

      config {
        image = "lscr.io/linuxserver/prowlarr:latest"
        ports = ["http"]

        volumes = [
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/data:/config",
          "/etc/localtime:/etc/localtime:ro",
        ]
      }

      # TODO: migrate to postgres
      env {
        PUID                   = "1000"
        PGID                   = "1000"
        TZ                     = "Europe/Dublin"
        PROWLARR__SERVER__PORT = "${NOMAD_PORT_http}"
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
