job "caddy" {
  datacenters = ["dc1"]
  type        = "system"

  group "caddy" {

    network {
      mode = "host"
      port "http" {
        static = 80
      }
      port "https" {
        static = 443
      }
      port "admin" {
        static = 2019
      }
      port "ssh" {
        static = 2222
      }
    }

    service {
      name = "caddy"
      port = "admin"

      check {
        type     = "http"
        port     = "admin"
        path     = "/config/"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "gatus.enable=true",
        "gatus.group=ingress",
        "gatus.url=http://caddy.service.consul:${NOMAD_PORT_admin}/_health",
      ]

    }

    update {
      max_parallel     = 1
      min_healthy_time = "15s"
      healthy_deadline = "2m"
      auto_revert      = true
    }

    task "caddy" {
      driver = "docker"

      config {
        image        = "ghcr.io/wizzdom/caddy-consul-docker:latest"
        network_mode = "host"
        entrypoint   = ["/usr/bin/caddy", "run", "--config", "/local/Caddyfile", "--adapter", "caddyfile", "--watch"]
      }

      template {
        destination = "secrets/.env"
        env         = true
        change_mode = "restart"
        data        = <<EOF
CADDY_EMAIL                     = {{ key "caddy/config/email" }}
CADDY_STORAGE_CONSUL_AES_KEY    = {{ key "consul/caddy/aes_key" }}
CADDY_DNS_CLOUDFLARE_API_TOKEN  = {{ key "caddy/cloudflare/api/token" }}
EOF
      }

      template {
        destination   = "local/Caddyfile"
        change_mode   = "signal"
        change_signal = "SIGUSR1"
        data          = <<EOF
{
  admin 0.0.0.0:{{ env "NOMAD_PORT_admin" }} # not exposed publicly
  email {$CADDY_EMAIL}

  metrics

  log {
    output stdout
    # format json
  }

  storage consul {
    address "{{ env "attr.unique.network.ip-address" }}:8500"
    prefix  "caddytls"
    aes_key {$CADDY_STORAGE_CONSUL_AES_KEY}
  }
}

# reuable parts
(tlsConfig) {
  tls {
    dns cloudflare {$CADDY_DNS_CLOUDFLARE_API_TOKEN}
  }
}

(securityHeaders) {
  header {
    Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
    X-Content-Type-Options    "nosniff"
    X-Frame-Options           "SAMEORIGIN"
    Referrer-Policy           "strict-origin-when-cross-origin"
    -Server
  }
}

# HTTP -> HTTPS redirect
:80 {
  redir https://{host}{uri} permanent
}

# healthcheck
:{{ env "NOMAD_PORT_admin" }} {
  route /_health {
        respond "OK"
    }
}

# grab domains from KV for cert gen
{{- range $domain := keyOrDefault "caddy/config/wildcard_domains" "" | split "," }}
{{- $domain = trimSpace $domain }}
{{- if ne $domain "" }}
{{ $domain }}, *.{{ $domain }} {
  import tlsConfig
}
{{- end }}
{{- end }}

# reverse proxy consul services with traefik-style tags
{{- range services }}
  {{- $service := .Name }}
  {{- $enabled := false }}
  {{- $host := "" }}

  {{- range .Tags }}
    {{- if . | regexMatch "caddy\\.enable=true" }}{{ $enabled = true }}{{ end }}
    {{- if . | regexMatch "caddy\\..+\\.rule=Host\\(['\"`]?([^'\"`]+)['\"`]?\\)" }}
      {{- $host = . | regexReplaceAll ".*Host\\(['\"`]?([^'\"`]+)['\"`]?\\).*" "$1" }}
    {{- end }}
  {{- end }}

  {{- if and $enabled $host }}
{{ $host }} {
  import tlsConfig
  import securityHeaders

  reverse_proxy {
    dynamic srv {
      name      {{ $service }}.service.consul
      refresh   30s
      dial_timeout        2s
      dial_fallback_delay -1s
    }

    lb_policy       round_robin
    lb_try_duration 10s
    lb_try_interval 250ms

    fail_duration    10s
    max_fails        3
    unhealthy_status 500 502 503 504
  }
}

  {{- end }}
{{- end }}
EOF
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }

    restart {
      attempts = 3
      interval = "5m"
      delay    = "15s"
      mode     = "fail"
    }
  }
}
