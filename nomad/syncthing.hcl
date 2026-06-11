job "syncthing" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "sync.wizzdom.xyz"
  }

  group "syncthing" {
    count = 1

    network {
      mode = "host"
      port "http" {
        to = 8384
      }
      port "sync" {
        to     = 22000
        static = 22000
      }
      port "discover" {
        to     = 21027
        static = 21027
      }
    }

    service {
      name = "syncthing"
      port = "http"

      check {
        type     = "http"
        path     = "/rest/noauth/health"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "caddy.enable=true",
        "caddy.http.routers.syncthing.rule=Host(`${NOMAD_META_domain}`)",
      ]
    }

    task "syncthing" {
      driver = "docker"

      config {
        image    = "lscr.io/linuxserver/syncthing:latest"
        hostname = "${NOMAD_META_domain}"
        ports    = ["http", "sync", "discover"]

        volumes = [
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/data:/config",
          "/mnt/media:/mnt/media",
          "/mnt/storage:/mnt/storage",
          "/mnt/backups:/mnt/backups",
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
