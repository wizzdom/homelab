job "searxng" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "search.wizzdom.xyz"
  }

  group "web" {
    network {
      port "http" {
        to = 8080
      }

    }

    service {
      name = "searxng"
      port = "http"

      check {
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "caddy.enable=true",
        "caddy.http.routers.searxng.rule=Host(`${NOMAD_META_domain}`)",
      ]
    }

    task "app" {
      driver = "docker"

      config {
        image = "docker.io/searxng/searxng:latest"
        ports = ["http"]

        volumes = [
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/searxng:/etc/searxng",
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/cache:/var/cache/searxng",
        ]
      }

      resources {
        memory = 300
      }

      template {
        destination = "local/.env"
        env         = true
        data        = <<EOH
SEARXNG_HOST=0.0.0.0
SEARXNG_PORT={{ env "NOMAD_PORT_http" }}

SEARXNG_BASE_URL=https://{{ env "NOMAD_META_domain" }}

SEARXNG_TRUSTED_PROXIES="127.0.0.0/8,192.168.0.0/16,172.16.0.0/12"
SEARXNG_VALKEY_URL=valkey://{{- range service "searxng-valkey" }}{{ .Address }}:{{ .Port }}{{- end }}/0

SEARXNG_PUBLIC_INSTANCE=true
FORCE_OWNERSHIP=true
EOH
      }
    }
  }

  group "backend" {
    count = 1

    ephemeral_disk {
      size    = 300 # MB
      migrate = true
    }

    network {
      port "valkey" {
        to = 6379
      }
    }

    service {
      name = "searxng-valkey"

      task = "valkey"
      port = "valkey"

      check {
        type     = "script"
        command  = "sh"
        args     = ["-c", "redis-cli ping || exit 1"]
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "valkey" {
      driver = "docker"

      config {
        image      = "valkey/valkey:9"
        force_pull = true
        ports      = ["valkey"]

        args = ["/local/valkey.conf"]
      }

      template {
        destination = "local/valkey.conf"
        data        = <<EOH
# save every 60 seconds if at least 100 keys have changed
save 60 100

dir {{ env "NOMAD_ALLOC_DIR" }}/data
EOH
      }

      resources {
        memory = 100
        cpu    = 100
      }
    }
  }
}

