job "mollysocket" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "molly.wizzdom.xyz"
  }

  group "web" {
    count = 1

    network {
      port "http" {}
    }

    service {
      name = "mollysocket"
      port = "http"

      check {
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "caddy.enable=true",
        "caddy.http.routers.mollysocket.rule=Host(`${NOMAD_META_domain}`)",
      ]
    }

    task "mollysocket" {
      driver = "docker"

      config {
        image   = "ghcr.io/mollyim/mollysocket:1"
        ports   = ["http"]
        command = "server"

        volumes = [
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/data:/data",
          "/etc/localtime:/etc/localtime:ro",
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        change_mode = "restart"
        data        = <<EOH
MOLLY_DB="/data/mollysocket.db" # sqlite smh...
MOLLY_ALLOWED_ENDPOINTS=["{{ env "NOMAD_META_domain" }}"]
MOLLY_ALLOWED_UUIDS=["*"]
MOLLY_VAPID_PRIVKEY="{{ key "mollysocket/vapid/privkey" }}"
MOLLY_HOST=0.0.0.0
MOLLY_PORT={{ env "NOMAD_PORT_http" }}
RUST_LOG=info
EOH
      }

      resources {
        cpu    = 50
        memory = 24
      }
    }
  }
}
