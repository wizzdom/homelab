job "radarr" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "radarr.wizzdom.xyz"
  }

  group "radarr" {
    count = 1

    network {
      port "http" {
        to = 7878
      }
    }

    service {
      name = "radarr"
      port = "http"

      check {
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "caddy.enable=true",
        "caddy.http.routers.radarr.rule=Host(`${NOMAD_META_domain}`)",
      ]
    }

    task "radarr" {
      driver = "docker"

      config {
        image = "lscr.io/linuxserver/radarr:latest"
        ports = ["http"]

        # TODO: migrate to postgres
        volumes = [
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/data:/config",
          "/mnt/media:/data",
        ]
      }

      env {
        PUID = "1000"
        PGID = "1000"
        TZ   = "Europe/Dublin"
      }

      resources {
        cpu    = 300
        memory = 256
      }
    }
  }
}
