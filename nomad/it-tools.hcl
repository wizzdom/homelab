job "it-tools" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "tools.wizzdom.xyz"
  }

  group "web" {
    count = 1

    network {
      port "http" {
        to = 80
      }
    }

    service {
      name = "it-tools"
      port = "http"

      check {
        type     = "http"
        path     = "/"
        interval = "60s"
        timeout  = "2s"
      }

      tags = [
        "caddy.enable=true",
        "caddy.http.routers.it-tools.rule=Host(`${NOMAD_META_domain}`)",
      ]
    }

    task "app" {
      driver = "docker"

      config {
        image = "corentinth/it-tools:latest"
        ports = ["http"]
      }

      resources {
        cpu    = 20
        memory = 20
      }
    }
  }
}

