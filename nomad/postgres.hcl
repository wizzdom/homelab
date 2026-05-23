job "postgres" {
  datacenters = ["dc1"]
  type        = "service"

  group "patroni" {
    count = 3

    constraint {
      operator = "distinct_hosts"
      value    = "true"
    }

    network {
      port "postgres" {
        static = 5432
      }
      port "api" {
        to = 8008
      }
    }

    update {
      max_parallel     = 1
      health_check     = "checks"
      min_healthy_time = "30s"
      healthy_deadline = "9m"
      auto_revert      = false
      stagger          = "60s"
    }

    restart {
      attempts = 3
      interval = "5m"
      delay    = "20s"
      mode     = "delay"
    }

    service {
      name = "patroni-api"
      port = "api"
      tags = ["patroni", "api"]

      check {
        type     = "http"
        path     = "/health"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "postgres" {
      driver       = "docker"
      kill_timeout = "60s"

      config {
        image = "ghcr.io/wizzdom/postgres-patroni-consul-docker:18"
        ports = ["postgres", "api"]
        args  = ["/local/patroni.yml"]

        volumes = [
          "/opt/${NOMAD_JOB_NAME}/${NOMAD_GROUP_NAME}:/var/lib/postgresql/data",
        ]

        # cap_add = ["SYS_NICE"]
      }

      env {
        # Patroni-recommended mitigation for Python 3.11+ memory issue
        MALLOC_ARENA_MAX    = "1"
        PG_MALLOC_ARENA_MAX = ""
      }

      template {
        destination = "local/patroni.yml"
        change_mode = "restart"
        data        = <<EOH
scope: postgres
namespace: /postgres/patroni/
name: {{ env "node.unique.name" }}

log:
  level: INFO
  format: '%(asctime)s %(levelname)s: %(message)s'

restapi:
  listen: 0.0.0.0:8008
  connect_address: {{ env "NOMAD_HOST_ADDR_api" }}
  authentication:
    username: {{ key "postgres/patroni/rest/user" }}
    password: '{{ key "postgres/patroni/rest/password" }}'

consul:
  host: {{ env "attr.unique.network.ip-address" }}:8500
  register_service: true
  scheme: http
  consistency: default

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    master_start_timeout: 300
    synchronous_mode: false
    postgresql:
      use_pg_rewind: true
      use_slots: true
      parameters:
        wal_level: replica
        hot_standby: "on"
        max_connections: 200
        max_wal_senders: 10
        max_replication_slots: 10
        max_active_replication_origins: 10
        wal_log_hints: "on"
        wal_keep_size: 512MB
        shared_buffers: 512MB
        effective_cache_size: 1536MB
        work_mem: 16MB
        maintenance_work_mem: 128MB
        # PG18 async I/O
        io_method: worker
        io_workers: 3
        # PG18: auto-invalidate dead slots
        idle_replication_slot_timeout: '1h'
        # Logging
        log_destination: stderr
        logging_collector: "off"
        log_min_duration_statement: 1000
        log_checkpoints: "on"
        log_connections: "on"
        log_disconnections: "on"
        log_lock_waits: "on"
        log_temp_files: 0
        log_line_prefix: '%t [%p]: db=%d,user=%u,app=%a,client=%h '

  initdb:
    - encoding: UTF8
    - data-checksums
    - locale-provider=builtin
    - builtin-locale=C.UTF-8

  pg_hba:
    - local all all trust
    - host all all 127.0.0.1/32 trust
    - host replication replicator 192.168.0.0/16 scram-sha-256
    - host replication replicator 172.17.0.0/16 scram-sha-256
    - host all all 192.168.0.0/16 scram-sha-256
    - host all all 172.17.0.0/16 scram-sha-256

  users:
    admin:
      password: '{{ key "postgres/admin/password" }}'
      options:
        - createrole
        - createdb

postgresql:
  listen: 0.0.0.0:5432
  connect_address: {{ env "NOMAD_HOST_ADDR_postgres" }}
  data_dir: /var/lib/postgresql/data
  bin_dir: /usr/local/bin
  pgpass: /tmp/pgpass
  parameters:
    password_encryption: scram-sha-256
  authentication:
    replication:
      username: {{ key "postgres/replicator/name" }}
      password: '{{ key "postgres/replicator/password" }}'
    superuser:
      username: {{ key "postgres/superuser/name" }}
      password: '{{ key "postgres/superuser/password" }}'
    rewind:
      username: {{ key "postgres/rewind/name" }}
      password: '{{ key "postgres/rewind/password" }}'
  remove_data_directory_on_rewind_failure: false
  remove_data_directory_on_diverged_timelines: false
  create_replica_methods:
    - basebackup
  basebackup:
    checkpoint: fast
    max-rate: '100M'

tags:
  nofailover: false
  noloadbalance: false
  clonefrom: false
  nosync: false
EOH
      }

      resources {
        cpu    = 2000
        memory = 2048
      }
    }
  }
}
