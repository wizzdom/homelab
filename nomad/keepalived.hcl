job "keepalived" {
  datacenters = ["dc1"]
  type        = "system"

  meta {
    virtual_ipaddress = "192.168.1.50"
  }

  group "vrrp" {
    network {
      mode = "host"
    }

    # service {
    #   name = "keepalived"
    #
    #   check {
    #     type     = "script"
    #     command  = "/bin/sh"
    #     args     = ["-c", "ip addr show | grep -q '192.168.1.50'"]
    #     interval = "10s"
    #     timeout  = "2s"
    #   }
    # }

    update {
      max_parallel     = 1
      min_healthy_time = "10s"
      healthy_deadline = "1m"
      auto_revert      = true
    }

    task "keepalived" {
      driver       = "docker"
      kill_signal  = "SIGTERM"
      kill_timeout = "15s"


      config {
        image   = "osixia/keepalived:2.3.4"
        cap_add = ["NET_ADMIN", "NET_RAW", "NET_BROADCAST"]

        args = [
          "--",
          "--dont-fork",
          "--log-console",
          "--log-detail",
        ]
      }

      env {
        KEEPALIVED_CONF = "/local/keepalived.conf"
      }

      template {
        destination = "local/keepalived.conf"
        change_mode = "noop"
        data        = <<EOF
global_defs {
  router_id {{ env "attr.unique.hostname" }}
  enable_script_security
}

vrrp_instance VI_1 {
  state BACKUP
  interface enp1s0 # TODO: template this based on network interface with default route
  virtual_router_id 51
  priority 150
  advert_int 1

  authentication {
    auth_type PASS
    auth_pass {{ key "keepalived/auth/pass" }}
  }

  unicast_src_ip {{ env "attr.unique.network.ip-address" }}

  unicast_peer {
    {{- range nodes }}
    {{- if ne .Address (env "attr.unique.network.ip-address") }}
    {{ .Address }}
    {{- end }}
    {{- end }}
  }

  virtual_ipaddress {
    {{ env "NOMAD_META_virtual_ipaddress" }}
  }
}
EOF
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }
  }
}

