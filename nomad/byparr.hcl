job "byparr" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "byparr.wizzdom.xyz"
  }

  group "byparr" {
    count = 1

    network {
      port "http" {
      }
    }

    service {
      name = "byparr"
      port = "http"

      # TODO: investigate health checks
      # check {
      #   type     = "http"
      #   path     = "/health"
      #   interval = "10s"
      #   timeout  = "2s"
      # }

      tags = [
        "caddy.enable=true",
        "caddy.http.routers.byparr.rule=Host(`${NOMAD_META_domain}`)",

        "gatus.enable=true",
        "gatus.group=tools",
        "gatus.url=https://${NOMAD_META_domain}/health",
      ]
    }

    task "byparr" {
      driver = "docker"

      config {
        image = "ghcr.io/thephaseless/byparr:latest"
        ports = ["http"]
      }

      resources {
        # python smh...
        cpu    = 800
        memory = 1024
      }

      env {
        HOST = "0.0.0.0"
        PORT = "${NOMAD_PORT_http}"
      }
    }
  }
}
