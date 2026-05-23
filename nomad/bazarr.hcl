job "bazarr" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "bazarr.wizzdom.xyz"
  }

  group "bazarr" {
    count = 1

    network {
      port "http" {
        to = 6767
      }
    }

    service {
      name = "bazarr"
      port = "http"

      tags = [
        "caddy.enable=true",
        "caddy.http.routers.bazarr.rule=Host(`${NOMAD_META_domain}`)",
      ]
    }

    task "bazarr" {
      driver = "docker"

      config {
        image = "lscr.io/linuxserver/bazarr:latest"
        ports = ["http"]

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
