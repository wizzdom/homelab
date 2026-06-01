job "qbittorrent" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "qbittorrent.wizzdom.xyz"
  }

  group "qbittorrent" {
    count = 1

    network {
      port "http" {
        to = 8080
      }

      port "bittorrent" {
        to     = 6881
        static = 6881
      }
    }

    service {
      name = "qbittorrent"
      port = "http"

      # TODO: add health check

      tags = [
        "caddy.enable=true",
        "caddy.http.routers.qbittorrent.rule=Host(`${NOMAD_META_domain}`)",
      ]
    }

    # TODO: add gluetun for VPN support
    task "qbittorrent" {
      driver = "docker"

      action "remove-lockfile" {
        command = "rm"
        args = [
          "-f",
          "/config/qBittorrent/lockfile"
        ]
      }

      config {
        image = "lscr.io/linuxserver/qbittorrent:latest"
        ports = ["http", "bittorrent"]

        volumes = [
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/data:/config",
          "/mnt/media/torrents:/data/torrents",
        ]
      }

      env {
        PUID            = "1000"
        PGID            = "1000"
        TZ              = "Europe/Dublin"
        WEBUI_PORT      = "${NOMAD_PORT_http}"
        TORRENTING_PORT = "${NOMAD_PORT_bittorrent}"
      }

      resources {
        cpu    = 500
        memory = 2048
      }
    }
  }
}
