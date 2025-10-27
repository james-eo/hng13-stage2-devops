#!/bin/sh
set -e

# nginx entrypoint script for Blue/Green deployment configuration
# This script generates the nginx configuration based on ACTIVE_POOL environment variable

CONF_FILE="/etc/nginx/conf.d/default.conf"
ACTIVE_POOL=${ACTIVE_POOL:-blue}
PORT=${PORT:-8080}

echo "Configuring nginx for active pool: $ACTIVE_POOL"

# Function to generate nginx configuration
generate_config() {
    local primary_server=""
    local backup_server=""
    
    if [ "$ACTIVE_POOL" = "blue" ]; then
        primary_server="app_blue:$PORT"
        backup_server="app_green:$PORT backup"
    else
        primary_server="app_green:$PORT"
        backup_server="app_blue:$PORT backup"
    fi

    cat > "$CONF_FILE" << EOF
# Blue/Green deployment configuration
# Active pool: $ACTIVE_POOL
# Generated at: $(date)

upstream backend {
    # Primary server (active pool)
    server $primary_server max_fails=1 fail_timeout=2s;
    
    # Backup server (standby pool)
    server $backup_server;
    
    # Connection pooling and keepalive for performance
    keepalive 32;
}

# Rate limiting for chaos testing protection
limit_req_zone \$binary_remote_addr zone=api:10m rate=100r/s;

server {
    listen 80;
    server_name _;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    
    # Logging configuration
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log warn;
    
    location / {
        # Rate limiting with burst allowance
        limit_req zone=api burst=20 nodelay;
        
        # Proxy configuration with tight timeouts for fast failover
        proxy_pass http://backend;
        proxy_http_version 1.1;
        
        # Connection timeouts (aggressive for fast failover)
        proxy_connect_timeout 1s;
        proxy_send_timeout 3s;
        proxy_read_timeout 3s;
        
        # Retry configuration for automatic failover
        proxy_next_upstream error timeout http_502 http_503 http_504 http_500;
        proxy_next_upstream_tries 2;
        proxy_next_upstream_timeout 5s;
        
        # Header forwarding (preserve application headers)
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Connection "";
        
        # Critical: Forward application-specific headers unchanged
        proxy_pass_header X-App-Pool;
        proxy_pass_header X-Release-Id;
        
        # Disable buffering for real-time responses
        proxy_buffering off;
        proxy_cache off;
    }
    
    # Health check endpoint for nginx itself
    location /nginx-health {
        access_log off;
        return 200 "nginx healthy\n";
        add_header Content-Type text/plain;
    }
    
    # Nginx status for monitoring
    location /nginx-status {
        stub_status on;
        access_log off;
        allow 127.0.0.1;
        allow 172.16.0.0/12;  # Docker networks
        deny all;
    }
}
EOF
}

# Generate initial configuration
generate_config

echo "nginx configuration generated successfully"
echo "Active pool: $ACTIVE_POOL"
echo "Configuration written to: $CONF_FILE"

# Validate configuration
nginx -t

echo "nginx configuration validation passed"