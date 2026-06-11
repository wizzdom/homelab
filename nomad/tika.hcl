job "tika" {
  datacenters = ["dc1"]
  type        = "service"

  group "tika" {
    count = 1

    network {
      port "http" {
        to = 9998
      }
    }

    service {
      name = "tika"
      port = "http"

      check {
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "tika" {
      driver = "docker"

      config {
        image    = "docker.io/apache/tika:latest"
        hostname = "${NOMAD_JOB_NAME}"
        ports    = ["http"]
      }

      resources {
        cpu    = 300
        memory = 256
      }
    }
  }
}
