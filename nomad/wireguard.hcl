job "wireguard" {
  datacenters = ["dc1"]
  type        = "service"

  constraint {
    attribute = "${attr.unique.hostname}"
    value     = "trinity"
  }

  meta {
    domain = "wg.wizzdom.xyz"
  }

  group "wg-easy" {
    count = 1

    network {
      port "webui" {}
      port "wireguard" {
        to     = 51820
        static = 51820
      }
    }

    service {
      name = "wireguard"
      port = "webui"

      check {
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "caddy.enable=true",
        "caddy.http.routers.wireguard.rule=Host(`${NOMAD_META_domain}`)",
      ]
    }

    task "wg-easy" {
      driver = "docker"

      config {
        image    = "ghcr.io/wg-easy/wg-easy:15"
        hostname = "${NOMAD_META_domain}"
        ports    = ["webui", "wireguard"]
        cap_add  = ["NET_ADMIN", "SYS_MODULE"] # NET_RAW maybe?

        volumes = [
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/config:/etc/wireguard",
          "/lib/modules:/lib/modules:ro",
        ]
        sysctl = {
          "net.ipv4.ip_forward" : "1"
          "net.ipv4.conf.all.src_valid_mark" : "1"
          "net.ipv6.conf.all.disable_ipv6" : "0"
          "net.ipv6.conf.all.forwarding" : "1"
          "net.ipv6.conf.default.forwarding" : "1"
        }
      }


      env {
        PUID = "1000"
        PGID = "1000"
        TZ   = "Europe/Dublin"
        PORT = "${NOMAD_PORT_webui}"
        HOST = "0.0.0.0"
      }

      resources {
        cpu    = 100
        memory = 96
      }
    }
  }
}
