job "seerr" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "requests.wizzdom.xyz"
  }

  group "seerr" {
    count = 1

    network {
      port "http" {}
    }

    service {
      name = "seerr"
      port = "http"

      check {
        type     = "http"
        path     = "/api/v1/settings/public"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "caddy.enable=true",
        "caddy.http.routers.seerr.rule=Host(`${NOMAD_META_domain}`)",
      ]
    }

    task "seerr" {
      driver = "docker"

      config {
        image = "ghcr.io/seerr-team/seerr:latest"
        ports = ["http"]

        volumes = [
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/app/config",
          "/etc/localtime:/etc/localtime:ro",
        ]
      }

      env {
        LOG_LEVEL = "debug"
        TZ        = "Europe/Dublin"
        PORT      = "${NOMAD_PORT_http}"
      }
      # TODO: migrate to postgres

      resources {
        cpu    = 300
        memory = 512
      }
    }
  }
}
