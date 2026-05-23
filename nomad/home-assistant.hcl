job "home-assistant" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "ha.wizzdom.xyz"
  }

  group "home-assistant" {
    count = 1

    network {
      port "http" {
        to = 8123
      }
    }

    service {
      name = "home-assistant"
      port = "http"

      check {
        type     = "http"
        path     = "/" # no healthcheck endpoint, expecting a HTTP 405
        interval = "60s"
        timeout  = "2s"
      }

      tags = [
        "caddy.enable=true",
        "caddy.http.routers.ha.rule=Host(`${NOMAD_META_domain}`)",
      ]
    }

    task "home-assistant" {
      driver = "docker"

      config {
        image = "ghcr.io/home-assistant/home-assistant:stable"
        ports = ["http"]

        # TODO: migrate to postgresql or something, sqlite is not ideal
        volumes = [
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/config:/config:rw",
          "local/configuration.yaml:/config/configuration.yaml:ro",
          "/etc/localtime:/etc/localtime:ro",
          "/run/dbus:/run/dbus:ro",
        ]
      }

      template {
        destination = "local/configuration.yaml"
        change_mode = "restart"
        data        = <<EOF
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 172.16.0.0/12
    - 10.0.0.0/8
    - 192.168.0.0/16

# Loads default set of integrations. Do not remove.
default_config:

# Load frontend themes from the themes folder
frontend:
  themes: !include_dir_merge_named themes

automation: !include automations.yaml
script: !include scripts.yaml
scene: !include scenes.yaml
EOF
      }

      resources {
        cpu    = 500
        memory = 1024
      }
    }
  }
}
