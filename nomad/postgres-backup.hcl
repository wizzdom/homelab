job "postgres-backup" {
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    crons            = ["0 */3 * * * *"]
    prohibit_overlap = true
  }

  group "db-backup" {
    task "postgres-backup" {
      driver = "docker"

      config {
        image   = "postgres:18-alpine"
        command = "/bin/bash"
        args    = ["/local/script.sh"]
        volumes = [
          "/mnt/backups/nomad/postgres:/backups",
        ]
      }

      template {
        destination = "local/pgpass"
        perms       = "0600"
        data        = <<EOH
master.postgres.service.consul:5432:*:{{ key "postgres/superuser/name" }}:{{ key "postgres/superuser/password" }}
EOH
      }

      template {
        destination = "local/script.sh"
        data        = <<EOH
#!/bin/bash
set -euo pipefail

dir=/backups
mkdir -p "$dir"
file="${dir}/postgresql-backup-$(date +%Y-%m-%d_%H-%M-%S).sql.gz"

echo "Starting backup -> $file"

pg_dumpall \
  -h master.postgres.service.consul \
  -p 5432 \
  -U {{ key "postgres/superuser/name" }} \
  | gzip > "$file"

# Prune backups older than 3 days
find "$dir" -name 'postgresql-backup*.sql.gz' -ctime +3 -delete || true

if [ -s "$file" ]; then
  echo "Backup successful: $file ($(du -sh "$file" | cut -f1))"
  exit 0
else
  rm -f "$file"
  echo "Backup FAILED: output file is empty" >&2
  # curl -sf -H "Content-Type: application/json" \
  #   -d "{\"content\": \"<@&585512338728419341> \`PostgreSQL\` backup **FAILED**\nFile: \`${file}\`\nDate: \`$(TZ=Europe/Dublin date)\`\"}" \
  #   {{ key "postgres/backup/webhook/discord" }} || true
  exit 1
fi
EOH
      }

      env {
        PGPASSFILE = "/local/pgpass"
      }

      resources {
        cpu    = 500
        memory = 256
      }
    }
  }
}
