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

        "gatus.enable=true",
        "gatus.group=media",
        "gatus.url=https://${NOMAD_META_domain}/",
      ]
    }

    ephemeral_disk { # cache
      size    = 3000 # MB
      migrate = true
      sticky  = true # try to reschedule on same node
    }

    task "jellyfin" {
      driver = "docker"

      resources {
        cpu    = 1000
        memory = 2048
      }

      config {
        image = "lscr.io/linuxserver/jellyfin:latest"
        ports = ["http"]

        devices = [
          {
            host_path = "/dev/dri/card0"
          },
          {
            host_path = "/dev/dri/renderD128"
          }
        ]

        volumes = [
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/data:/config",
          "/mnt/media/media:/data/media",
          "/etc/localtime:/etc/localtime:ro",
        ]

        mount {
          type     = "tmpfs"
          target   = "/transcode"
          readonly = false
          tmpfs_options {
            size = 4294967296 # 4GB
          }
        }
      }

      env {
        PUID                        = "1000"
        PGID                        = "1000"
        TZ                          = "Europe/Dublin"
        SUP_GROUP_IDS               = "109,44,992"
        JELLYFIN_PublishedServerUrl = "https://${NOMAD_META_domain}"
        DOCKER_MODS                 = "linuxserver/mods:jellyfin-opencl-intel"
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
