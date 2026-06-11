job "gotenberg" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    src  = "https://github.com/gotenberg/gotenberg"
    docs = "https://gotenberg.dev/docs/getting-started/introduction"
  }

  group "gotenberg" {
    count = 1

    network {
      port "http" {}
    }

    service {
      name = "gotenberg"
      port = "http"

      check {
        type     = "http"
        path     = "/health"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "gotenberg" {
      driver = "docker"

      config {
        image    = "gotenberg/gotenberg:8"
        hostname = "${NOMAD_JOB_NAME}"
        ports    = ["http"]
      }

      env {
        PUID        = "1000"
        PGID        = "1000"
        TZ          = "Europe/Dublin"
        API_PORT    = "${NOMAD_PORT_http}"
        API_BIND_IP = "0.0.0.0"
        # API_DOWNLOAD_FROM_ALLOW_LIST =

        # source: https://github.com/paperless-ngx/paperless-ngx/blob/dev/docker/compose/docker-compose.postgres-tika.yml
        CHROMIUM_DISABLE_JAVASCRIPT = "true"
        CHROMIUM_ALLOW_LIST         = "file:///tmp/.*"
      }

      resources {
        cpu    = 300
        memory = 256
      }
    }
  }
}
