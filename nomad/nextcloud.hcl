job "nextcloud" {
  datacenters = ["dc1"]
  type        = "service"

  meta {
    domain = "cloud.wizzdom.xyz"
  }

  group "web" {
    count = 1

    ephemeral_disk {
      size    = 2048 # MB
      migrate = true # copies data to new alloc
      sticky  = true # try to reschedule on same node
    }

    network {
      port "http" {
        to = 80
      }
      port "fpm" {
        to = 9000
      }
      port "valkey" {
        to = 6379
      }
    }

    service {
      name = "nextcloud"
      port = "http"

      tags = [
        "caddy.enable=true",
        "caddy.http.routers.nextcloud.rule=Host(`${NOMAD_META_domain}`)",
        "gatus.enable=true",
        "gatus.group=productivity",
        "gatus.url=https://${NOMAD_META_domain}/",
      ]
    }

    task "app" {
      driver = "docker"

      config {
        image = "nextcloud:33-fpm-alpine"
        ports = ["fpm"]

        volumes = [
          "${NOMAD_ALLOC_DIR}/data/html:/var/www/html",

          # only mount these dirs, the rest is kept container on SSD, making upgrades faster
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/data:/var/www/html/data",
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/config:/var/www/html/config",
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/custom_apps:/var/www/html/custom_apps",
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/themes:/var/www/html/themes",

          # PHP optimizations go brrr
          "local/zzz-fpm.conf:/usr/local/etc/php-fpm.d/zzz-custom.conf:ro",
          "local/nextcloud.ini:/usr/local/etc/php/conf.d/zzz-nextcloud.ini:ro",
          "local/apcu.config.php:/var/www/html/config/apcu.config.php:ro",
        ]
      }

      template {
        destination = "secrets/nextcloud.env"
        env         = true
        data        = <<EOF
POSTGRES_DB={{ key "nextcloud/db/name" }}
POSTGRES_USER={{ key "nextcloud/db/user" }}
POSTGRES_PASSWORD={{ key "nextcloud/db/password" }}
POSTGRES_HOST=master.postgres.service.consul
POSTGRES_PORT=5432

NEXTCLOUD_ADMIN_USER={{ key "nextcloud/admin/name" }}
NEXTCLOUD_ADMIN_PASSWORD={{ key "nextcloud/admin/password" }}
NEXTCLOUD_DATA_DIR=/var/www/html/data
NEXTCLOUD_TRUSTED_DOMAINS={{ env "NOMAD_META_domain" }}
TRUSTED_PROXIES=10.0.0.0/8 172.17.0.0/16 192.168.0.0/16
NEXTCLOUD_UPDATE=1
NEXTCLOUD_INIT_HTACCESS=true

{{- range service "nextcloud-valkey" }}
REDIS_HOST={{ .Address }}
REDIS_HOST_PORT={{ .Port }}
{{- end }}

SMTP_HOST={{ key "nextcloud/smtp/host" }}
SMTP_SECURE=ssl
SMTP_PORT=465
SMTP_AUTHTYPE=PLAIN
SMTP_NAME={{ key "nextcloud/smtp/name" }}
SMTP_PASSWORD={{ key "nextcloud/smtp/password" }}
MAIL_FROM_ADDRESS={{ key "nextcloud/smtp/from" }}
MAIL_DOMAIN={{ key "nextcloud/smtp/domain" }}

# OBJECTSTORE_S3_BUCKET: The name of the bucket that Nextcloud should store the data in
# OBJECTSTORE_S3_REGION: The region that the S3 bucket resides in
# OBJECTSTORE_S3_HOST: The hostname of the object storage server
# OBJECTSTORE_S3_PORT: The port that the object storage server is being served over
# OBJECTSTORE_S3_KEY: AWS style access key
# OBJECTSTORE_S3_SECRET: AWS style secret access key
# OBJECTSTORE_S3_STORAGE_CLASS: The storage class to use when adding objects to the bucket
# OBJECTSTORE_S3_SSL (default: true): Whether or not SSL/TLS should be used to communicate with object storage server
# OBJECTSTORE_S3_USEPATH_STYLE (default: false): Not required for AWS S3
# OBJECTSTORE_S3_LEGACYAUTH (default: false): Not required for AWS S3
# OBJECTSTORE_S3_OBJECT_PREFIX (default: urn:oid:): Prefix to prepend to the fileid
# OBJECTSTORE_S3_AUTOCREATE (default: true): Create the container if it does not exist
# OBJECTSTORE_S3_SSE_C_KEY (not set by default): Base64 encoded key with a maximum length of 32 bytes for server side encryption (SSE-C)

PHP_MEMORY_LIMIT=1024M
PHP_UPLOAD_LIMIT=10G
PHP_OPCACHE_MEMORY_CONSUMPTION=256
EOF
      }

      template {
        destination = "local/zzz-fpm.conf"
        data        = <<EOF
[www]
pm = dynamic
pm.max_children = 20
pm.start_servers = 8
pm.min_spare_servers = 5
pm.max_spare_servers = 10
pm.max_requests = 500
request_terminate_timeout = 300s
EOF
      }

      template {
        destination = "local/nextcloud.ini"
        data        = <<EOF
; OPcache
opcache.enable=1
opcache.memory_consumption=256
opcache.interned_strings_buffer=32
opcache.max_accelerated_files=100000
opcache.save_comments=1
opcache.revalidate_freq=60

opcache.jit=1255
opcache.jit_buffer_size=256M

apc.enable_cli=1
apc.shm_size=128M

memory_limit = 1024M

upload_max_filesize = 10G
post_max_size       = 10G

max_execution_time  = 3600
max_input_time      = 3600

; Required by Nextcloud docs
output_buffering    = Off

; skip stat() checks - Nextcloud doesn't use them
realpath_cache_size = 4096k
realpath_cache_ttl  = 600
EOF
      }

      template {
        destination = "local/apcu.config.php"
        data        = <<EOF
<?php
$CONFIG = [
  'memcache.local' => '\OC\Memcache\APCu',
];
EOF
      }

      resources {
        cpu    = 500
        memory = 3072
      }
    }
    task "nginx" {
      driver = "docker"
      config {
        image = "nginx:alpine"
        ports = ["http"]
        volumes = [
          "${NOMAD_ALLOC_DIR}/data/html:/var/www/html:ro",

          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/data:/var/www/html/data:ro",
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/config:/var/www/html/config:ro",
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/custom_apps:/var/www/html/custom_apps:ro",
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/themes:/var/www/html/themes:ro",

          "local/nginx.conf:/etc/nginx/nginx.conf:ro",
        ]
        group_add = [82] # www-data in alpine
      }
      template {
        destination = "local/nginx.conf"
        data        = <<EOH
# copied from nextcloud example and tweaked - source: https://github.com/nextcloud/docker/blob/master/.examples/docker-compose/with-nginx-proxy/postgres/fpm/web/nginx.conf
worker_processes auto;

error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;

events {
    worker_connections  1024;
}


http {
    include mime.types;
    default_type  application/octet-stream;
    types {
        text/javascript mjs;
    }

    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile        on;
    tcp_nopush      on;   # batch headers/data into single packet
    tcp_nodelay     on;   # flush immediately after tcp_nopush sends


    # Prevent nginx HTTP Server Detection
    server_tokens   off;

    # Unwrap X-Forwarded-For from Caddy so PHP sees the real IP
    # set_real_ip_from  192.168.1.10;   # Caddy's IP
    set_real_ip_from  10.0.0.0/8;
    set_real_ip_from  172.17.0.0/16;
    set_real_ip_from  192.168.0.0/16;
    real_ip_header    X-Forwarded-For;
    real_ip_recursive on;

    keepalive_timeout  65;

    # Set the `immutable` cache control options only for assets with a cache busting `v` argument
    map $arg_v $asset_immutable {
        "" "";
    default ", immutable";
    }

    gzip  on;

    upstream php-handler {
        zone backends 64k;
        server {{ env "NOMAD_ADDR_fpm" }};
        keepalive 16;
    }

    server {
        listen 80;

        # HSTS settings
        # WARNING: Only add the preload option once you read about
        # the consequences in https://hstspreload.org/. This option
        # will add the domain to a hardcoded list that is shipped
        # in all major browsers and getting removed from this list
        # could take several months.
        add_header Strict-Transport-Security "max-age=15768000; includeSubDomains; preload;" always;

        # set max upload size and increase upload timeout:
        client_max_body_size 10G;
        client_body_timeout 300s;
        fastcgi_buffer_size 128k;
        fastcgi_buffers 4 256k;
        fastcgi_busy_buffers_size 256k;

        # The settings allows you to optimize the HTTP2 bandwidth.
        # See https://blog.cloudflare.com/delivering-http-2-upload-speed-improvements/
        # for tuning hints
        client_body_buffer_size 512k;

        # Enable gzip but do not remove ETag headers
        gzip on;
        gzip_vary on;
        gzip_comp_level 4;
        gzip_min_length 256;
        gzip_proxied expired no-cache no-store private no_last_modified no_etag auth;
        gzip_types application/atom+xml text/javascript application/javascript application/json application/ld+json application/manifest+json application/rss+xml application/vnd.geo+json application/vnd.ms-fontobject application/wasm application/x-font-ttf application/x-web-app-manifest+json application/xhtml+xml application/xml font/opentype image/bmp image/svg+xml image/x-icon text/cache-manifest text/css text/plain text/vcard text/vnd.rim.location.xloc text/vtt text/x-component text/x-cross-domain-policy;

        # HTTP response headers borrowed from Nextcloud `.htaccess`
        add_header Referrer-Policy                      "no-referrer"       always;
        add_header X-Content-Type-Options               "nosniff"           always;
        add_header X-Frame-Options                      "SAMEORIGIN"        always;
        add_header X-Permitted-Cross-Domain-Policies    "none"              always;
        add_header X-Robots-Tag                         "noindex, nofollow" always;

        # Remove X-Powered-By, which is an information leak
        fastcgi_hide_header X-Powered-By;

        # Path to the root of your installation
        root /var/www/html;

        # Specify how to handle directories -- specifying `/index.php$request_uri`
        # here as the fallback means that Nginx always exhibits the desired behaviour
        # when a client requests a path that corresponds to a directory that exists
        # on the server. In particular, if that directory contains an index.php file,
        # that file is correctly served; if it doesn't, then the request is passed to
        # the front-end controller. This consistent behaviour means that we don't need
        # to specify custom rules for certain paths (e.g. images and other assets,
        # `/updater`, `/ocm-provider`, `/ocs-provider`), and thus
        # `try_files $uri $uri/ /index.php$request_uri`
        # always provides the desired behaviour.
        index index.php index.html /index.php$request_uri;

        # Rule borrowed from `.htaccess` to handle Microsoft DAV clients
        location = / {
            if ( $http_user_agent ~ ^DavClnt ) {
                return 302 /remote.php/webdav/$is_args$args;
            }
        }

        location = /robots.txt {
            allow all;
            log_not_found off;
            access_log off;
        }

        # Make a regex exception for `/.well-known` so that clients can still
        # access it despite the existence of the regex rule
        # `location ~ /(\.|autotest|...)` which would otherwise handle requests
        # for `/.well-known`.
        location ^~ /.well-known {
            # The rules in this block are an adaptation of the rules
            # in `.htaccess` that concern `/.well-known`.

            location = /.well-known/carddav { return 301 /remote.php/dav/; }
            location = /.well-known/caldav  { return 301 /remote.php/dav/; }

            location /.well-known/acme-challenge    { try_files $uri $uri/ =404; }
            location /.well-known/pki-validation    { try_files $uri $uri/ =404; }

            # Let Nextcloud's API for `/.well-known` URIs handle all other
            # requests by passing them to the front-end controller.
            return 301 /index.php$request_uri;
        }

        # Rules borrowed from `.htaccess` to hide certain paths from clients
        location ~ ^/(?:build|tests|config|lib|3rdparty|templates|data)(?:$|/)  { return 404; }
        location ~ ^/(?:\.|autotest|occ|issue|indie|db_|console)                { return 404; }

        # Ensure this block, which passes PHP files to the PHP process, is above the blocks
        # which handle static assets (as seen below). If this block is not declared first,
        # then Nginx will encounter an infinite rewriting loop when it prepends `/index.php`
        # to the URI, resulting in a HTTP 500 error response.
        location ~ \.php(?:$|/) {
            # Required for legacy support
            rewrite ^/(?!index|remote|public|cron|core\/ajax\/update|status|ocs\/v[12]|updater\/.+|ocs-provider\/.+|.+\/richdocumentscode(_arm64)?\/proxy) /index.php$request_uri;

            fastcgi_split_path_info ^(.+?\.php)(/.*)$;
            set $path_info $fastcgi_path_info;

            try_files $fastcgi_script_name =404;

            include fastcgi_params;
            fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
            fastcgi_param PATH_INFO $path_info;
            fastcgi_param HTTPS on;

            fastcgi_param modHeadersAvailable true;         # Avoid sending the security headers twice
            fastcgi_param front_controller_active true;     # Enable pretty urls
            fastcgi_pass php-handler;
            fastcgi_keep_conn on;

            fastcgi_intercept_errors on;
            fastcgi_request_buffering on;                   # Required as PHP-FPM does not support chunked transfer encoding and requires a valid ContentLength header.

            fastcgi_max_temp_file_size 0;

            fastcgi_read_timeout 300s;  # match FPM's request_terminate_timeout
        }

        # Serve static files
        location ~ \.(?:css|js|mjs|svg|gif|ico|jpg|png|webp|wasm|tflite|map|ogg|flac|mp4|webm)$ {
            try_files $uri /index.php$request_uri;
            add_header Cache-Control "public, max-age=15778463$asset_immutable";
            add_header Referrer-Policy                   "no-referrer"       always;
            add_header X-Content-Type-Options            "nosniff"           always;
            add_header X-Frame-Options                   "SAMEORIGIN"        always;
            add_header X-Permitted-Cross-Domain-Policies "none"              always;
            add_header X-Robots-Tag                      "noindex, nofollow" always;
            access_log off;     # Optional: Don't log access to assets
        }

        location ~ \.(otf|woff2?)$ {
            try_files $uri /index.php$request_uri;
            expires 7d;         # Cache-Control policy borrowed from `.htaccess`
            access_log off;     # Optional: Don't log access to assets
        }

        # Rule borrowed from `.htaccess`
        location /remote {
            return 301 /remote.php$request_uri;
        }

        location / {
            try_files $uri $uri/ /index.php$request_uri;
        }
    }
}
EOH
      }
      resources {
        cpu    = 300
        memory = 256
      }

    }

    task "cron" {
      driver = "docker"
      user   = "82" # www-data in Alpine

      lifecycle {
        hook    = "poststart"
        sidecar = true
      }

      config {
        image   = "nextcloud:33-fpm-alpine"
        command = "/bin/sh"
        args    = ["-c", "while true; do php -f /var/www/html/cron.php; sleep 300; done"] # cron job to run background tasks
        volumes = [
          "${NOMAD_ALLOC_DIR}/data/html:/var/www/html",

          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/data:/var/www/html/data",
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/config:/var/www/html/config",
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/custom_apps:/var/www/html/custom_apps",
          "/mnt/storage/nomad/${NOMAD_JOB_NAME}/themes:/var/www/html/themes",

          "local/nextcloud.ini:/usr/local/etc/php/conf.d/zzz-nextcloud.ini:ro",
        ]
      }

      template {
        destination = "secrets/nextcloud.env"
        env         = true
        data        = <<EOF
POSTGRES_DB={{ key "nextcloud/db/name" }}
POSTGRES_USER={{ key "nextcloud/db/user" }}
POSTGRES_PASSWORD={{ key "nextcloud/db/password" }}
POSTGRES_HOST=master.postgres.service.consul
{{- range service "nextcloud-valkey" }}
REDIS_HOST={{ .Address }}
REDIS_HOST_PORT={{ .Port }}
{{- end }}
EOF
      }

      template {
        destination = "local/nextcloud.ini"
        data        = <<EOF
opcache.enable=1
opcache.enable_cli=1
opcache.memory_consumption=128
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=100000
opcache.save_comments=1
memory_limit = 1024M
max_execution_time = 3600
EOF
      }


      resources {
        cpu    = 200
        memory = 400
      }
    }

    task "db-init" {
      driver = "docker"

      lifecycle {
        hook    = "prestart"
        sidecar = false # must exit 0 before main task starts
      }

      config {
        image   = "postgres:18-alpine"
        command = "/bin/sh"
        args    = ["/local/init-db.sh"]
      }

      template {
        destination = "local/init-db.sh"
        perms       = "0755"
        data        = <<EOH
#!/bin/sh
set -eu

DB_NAME="{{ key "nextcloud/db/name" }}"
DB_USER="{{ key "nextcloud/db/user" }}"
DB_PASS="{{ key "nextcloud/db/password" }}"
PG_SUPERUSER="{{ key "postgres/superuser/name" }}"
PGHOST="master.postgres.service.consul"
PGPORT="5432"

PSQL="psql -v ON_ERROR_STOP=1 -U $PG_SUPERUSER -h $PGHOST -p $PGPORT"

echo "==> Creating role..."
$PSQL <<EOSQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$DB_USER') THEN
    CREATE ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS';
  END IF;
END
\$\$;
EOSQL

echo "==> Creating database..."
if ! $PSQL -tc "SELECT 1 FROM pg_database WHERE datname = '$DB_NAME'" | grep -q 1; then
  $PSQL -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"
fi

echo "==> DB init done."
EOH
      }

      template {
        destination = "local/pgpass"
        perms       = "0600"
        data        = <<EOH
master.postgres.service.consul:5432:*:{{ key "postgres/superuser/name" }}:{{ key "postgres/superuser/password" }}
EOH
      }

      env {
        PGPASSFILE = "/local/pgpass"
      }

      resources {
        cpu    = 50
        memory = 64
      }
    }

    service {
      name = "nextcloud-valkey"

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
maxmemory 150mb
maxmemory-policy noeviction

EOH
      }

      resources {
        memory = 200
        cpu    = 300
      }
    }
  }
}


