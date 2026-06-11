job "immich" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "immich.wizzdom.xyz"
  }

  group "api-server" {
    count = "1"
    network {
      port "api" {
        to = 2283
      }
    }

    service {
      name = "immich"

      task = "server"
      port = "api"

      check {
        type     = "http"
        path     = "/api/server/ping"
        interval = "5s"
        timeout  = "2s"
      }

      tags = [
        "caddy.enable=true",
        "caddy.http.routers.immich.rule=Host(`${NOMAD_META_domain}`)",
      ]
    }

    # The main immich API server
    task "server" {
      driver = "docker"

      config {
        image      = "ghcr.io/immich-app/immich-server:release"
        force_pull = true
        ports      = ["api"]

        volumes = [
          "/mnt/photos/${NOMAD_JOB_NAME}/data:/data",
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        perms       = 400
        data        = <<EOH
NODE_ENV = "production"
IMMICH_MEDIA_LOCATION = "/data"
TZ = "Europe/Dublin"

# user and group ID
PUID = 1000
PGID = 1000

IMMICH_TELEMETRY_INCLUDE = "all"

IMMICH_WORKERS_INCLUDE = "api"

{{- range service "immich-postgres" }}
DB_URL=postgres://{{ key "immich/db/user" }}:{{ key "immich/db/password" }}@{{ .Address }}:{{ .Port }}/{{ key "immich/db/name" }}
{{- end }}
{{- range service "immich-valkey" }}
REDIS_HOSTNAME={{ .Address }}
REDIS_PORT={{ .Port }}
{{- end }}
EOH
      }

      resources {
        # memory = 2048
        memory = 4096
        cpu    = 1024
      }
    }
  }

  // --- Immich Worker ---
  group "worker" {
    count = "2"
    constraint {
      distinct_hosts = true
    }

    network {
      port "worker" {
        to = 2283
      }
    }

    service {
      name = "immich-worker"
      port = "worker"

      check {
        type     = "http"
        path     = "/api/server/ping"
        interval = "5s"
        timeout  = "2s"
      }
    }

    # task worker, doing all the processing async
    task "server" {
      driver = "docker"

      config {
        image      = "ghcr.io/immich-app/immich-server:release"
        ports      = ["worker"]
        force_pull = true
        group_add  = ["109", "44", "992"] # render, video, media

        volumes = [
          "/mnt/photos/${NOMAD_JOB_NAME}/data:/data",
        ]

        devices = [ # map Intel iGPU to container, allowing for Intel QuickSync hardware encoding
          {
            host_path = "/dev/dri/card0"
          },
          {
            host_path = "/dev/dri/renderD128"
          }
        ]
      }

      env {
      }

      template {
        destination = "local/.env"
        env         = true
        perms       = 400
        data        = <<EOH
NODE_ENV = "production"
IMMICH_MEDIA_LOCATION = "/data"
PUID = 1000
PGID = 1000
TZ = "Europe/Dublin"

{{- range service "immich-postgres" }}
DB_URL=postgres://{{ key "immich/db/user" }}:{{ key "immich/db/password" }}@{{ .Address }}:{{ .Port }}/immich
{{- end }}
{{- range service "immich-valkey" }}
REDIS_HOSTNAME={{ .Address }}
REDIS_PORT={{ .Port }}
{{- end }}
EOH
      }

      resources {
        memory = 3500
        cpu    = 1600
      }
    }
  }

  // --- Immich Machine Learning ---
  group "machine-learning" {
    count = "1"

    network {
      port "ml" {
        static = 13030
        # NOTE: add consul DNS entry to the ml workers page in admin web ui
      }
    }

    ephemeral_disk { # Used to cache the machine learning model
      size    = 3000 # MB
      migrate = true
    }

    service {
      name = "immich-ml"
      port = "ml"

      # check {
      #   type     = "http"
      #   path     = "/ping"
      #   interval = "5s"
      #   timeout  = "2s"
      # }
    }

    task "ml-worker" {
      driver = "docker"

      config {
        image      = "ghcr.io/immich-app/immich-machine-learning:release"
        force_pull = true
        ports      = ["ml"]
        group_add  = ["109", "44", "992"] # render, video, media
        devices = [                       # map Intel iGPU to container, allowing for Intel QuickSync hardware encoding
          {
            host_path = "/dev/dri/card0"
          },
          {
            host_path = "/dev/dri/renderD128"
          },
          {
            host_path          = "/dev/bus/usb"
            cgroup_permissions = "rwm"
          }
        ]
      }

      env {
        TMPDIR       = "/tmp"
        MPLCONFIGDIR = "/local/mplconfig"
        IMMICH_PORT  = "13030"

        TZ = "Europe/Dublin"

        MACHINE_LEARNING_CACHE_FOLDER    = "${NOMAD_ALLOC_DIR}/data/cache"
        MACHINE_LEARNING_MODEL_TTL       = 0 # don't unload the model cache, re-fetching slows down queries a lot
        MACHINE_LEARNING_REQUEST_THREADS = 4
        # add your models from Settings -> Machine Learning here
        MACHINE_LEARNING_PRELOAD__CLIP               = "ViT-B-16-SigLIP-256__webli"
        MACHINE_LEARNING_PRELOAD__FACIAL_RECOGNITION = "antelopev2"
      }

      resources {
        memory = 3172
        cpu    = 1500
      }
    }
  }

  // --- Immich Postgres database and Valkey instance ---
  group "backend" {
    ephemeral_disk {
      size    = 300 # MB
      migrate = true
    }

    network {
      port "postgres" {
        to = 5432
      }

      port "valkey" {
        to = 6379
      }
    }

    service {
      name = "immich-postgres"

      task = "postgres"
      port = "postgres"

      check {
        type     = "script"
        command  = "sh"
        args     = ["-c", "psql -U $POSTGRES_USER -d immich  -c 'SELECT 1' || exit 1"]
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "postgres" {
      driver = "docker"

      # backs up the Postgres database and removes all files in the backup folder which are older than 3 days.
      action "backup-postgres" {
        command = "/bin/sh"
        args = ["-c", <<EOF
pg_dumpall -U "$POSTGRES_USER" | gzip --rsyncable > /var/lib/postgresql/data/backup/backup.$(date +"%Y%m%d%H%M").sql.gz
echo "cleaning up backup files older than 7 days ..."
find /var/lib/postgresql/data/backup -maxdepth 1 -type f -printf '%T@ %p\n' | sort -nr | tail -n +7 | cut -d' ' -f2- | xargs -r rm --
EOF
        ]
      }

      config {
        image      = "ghcr.io/immich-app/postgres:17-vectorchord0.5.3"
        ports      = ["postgres"]
        force_pull = true

        volumes = [
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/${NOMAD_TASK_NAME}:/var/lib/postgresql/data",
        ]
      }

      template {
        destination = "local/.env"
        env         = true
        perms       = 400
        data        = <<EOH
POSTGRES_USER        = {{ key "immich/db/user" }}
POSTGRES_NAME        = {{ key "immich/db/name" }}
POSTGRES_PASSWORD    = {{ key "immich/db/password" }}
POSTGRES_INITDB_ARGS = '--data-checksums'
DB_STORAGE_TYPE      = 'HDD'
EOH
      }

      resources {
        cpu    = 1000
        memory = 1024
      }
    }

    service {
      name = "immich-valkey"

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

    # Valkey cache, used as an event queue to schedule jobs
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
        memory = 200
        cpu    = 300
      }
    }
  }
}
