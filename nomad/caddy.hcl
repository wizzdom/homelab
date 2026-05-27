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
        "gatus.url=icmp://caddy.service.consul/",
      ]

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
  admin 0.0.0.0:{{ env "NOMAD_PORT_admin" }} # not exposed publically
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

# HTTP -> HTTPS redirect
:80 {
  redir https://{host}{uri} permanent
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
  reverse_proxy {
    {{- range service $service }}
    to {{ .Address }}:{{ .Port }}
    {{- end }}
    lb_policy round_robin
    lb_try_duration 5s
    fail_duration 10s
    max_fails 3
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
  }
}
