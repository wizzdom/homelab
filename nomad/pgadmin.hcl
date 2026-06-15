job "pgadmin" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "pgadmin.wizzdom.xyz"
  }

  group "pgadmin" {
    count = 1

    network {
      port "http" {
        to = 80
      }
    }

    service {
      name = "pgadmin"
      port = "http"

      tags = [
        "caddy.enable=true",
        "caddy.http.routers.pgadmin.rule=Host(`${NOMAD_META_domain}`)",

        "gatus.enable=true",
        "gatus.group=administration",
        "gatus.url=https://${NOMAD_META_domain}/",
      ]
    }

    task "pgadmin" {
      driver         = "docker"
      kill_signal    = "SIGTERM"
      kill_timeout   = "30s"
      shutdown_delay = "5s"

      config {
        image = "dpage/pgadmin4:9"
        ports = ["http"]

        volumes = [
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}:/var/lib/pgadmin",
        ]
      }

      template {
        destination = "secrets/.env"
        env         = true
        data        = <<EOF
PUID = "1000"
PGID = "1000"
TZ   = "Europe/Dublin"

PGADMIN_DISABLE_POSTFIX = "true"

PGADMIN_DEFAULT_EMAIL = {{ key "pgadmin/admin/email" }}
PGADMIN_DEFAULT_PASSWORD = {{ key "pgadmin/admin/password" }}

PGADMIN_LISTEN_ADDRESS = 0.0.0.0
PGADMIN_LISTEN_PORT = {{ env "NOMAD_PORT_http" }}
PGADMIN_CONFIG_ENHANCED_COOKIE_PROTECTION=False # hsts is wack
EOF
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }
  }
}
