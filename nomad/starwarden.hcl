job "starwarden" {
  datacenters = ["dc1"]
  type        = "batch"

  meta {
    source      = "https://github.com/rtuszik/starwarden"
    description = "A tool to backup GitHub stars to Linkwarden"
  }

  periodic {
    crons            = ["0 */3 * * * *"]
    prohibit_overlap = true
  }

  group "starwarden" {
    task "app" {
      driver = "docker"

      config {
        image = "rtuszik/starwarden:latest"
        # bypass the container's internal cron
        command = "python"
        args    = ["/app/starwarden.py", "-id", "${COLLECTION_ID}"]
      }

      template {
        destination = "secrets/.env"
        env         = true
        data        = <<EOF
GITHUB_TOKEN        = {{ key "starwarden/github/token" }}
GITHUB_USERNAME     = {{ key "starwarden/github/user" }}

LINKWARDEN_URL      = https://links.wizzdom.xyz
LINKWARDEN_TOKEN    = {{ key "starwarden/linkwarden/token" }}

COLLECTION_ID       = 176

# APPRISE_URLS

OPT_TAG             = true
OPT_TAG_GITHUB      = true
OPT_TAG_GITHUBSTARS = true
OPT_TAG_LANGUAGE    = true
OPT_TAG_USERNAME    = true
OPT_TAG_CUSTOM      = false
EOF
      }
    }
  }
}
