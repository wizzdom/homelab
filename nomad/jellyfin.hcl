job "jellyfin" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "jellyfin.wizzdom.xyz"
  }

  group "jellyfin" {
    count = 1

    network {
      port "http" {
        to = 8096
      }
    }

    service {
      name = "jellyfin"
      port = "http"

      check {
        type     = "http"
        path     = "/health"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "caddy.enable=true",
        "caddy.http.routers.jellyfin.rule=Host(`${NOMAD_META_domain}`)",
      ]
    }

    task "jellyfin" {
      driver = "docker"

      resources {
        cpu    = 1000
        memory = 1024
      }

      config {
        image = "lscr.io/linuxserver/jellyfin:latest"
        ports = ["http"]

        devices = [
          {
            host_path      = "/dev/dri"
            container_path = "/dev/dri"
          }
        ]

        volumes = [
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/data:/config",
          "/mnt/media/media:/data/media",
          "/etc/localtime:/etc/localtime:ro",
        ]
      }

      env {
        PUID                        = "1000"
        PGID                        = "1000"
        TZ                          = "Europe/Dublin"
        SUP_GROUP_IDS               = "109,44"
        JELLYFIN_PublishedServerUrl = "https://${NOMAD_META_domain}"
        # TODO: add jellyfin envvars for postgres once supported
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
