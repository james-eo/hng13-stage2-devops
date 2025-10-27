#!/usr/bin/env bash
set -euo pipefail

# Blue/Green Toggle Script
# Switches active pool and reloads nginx configuration

ENV_FILE="${ENV_FILE:-/home/freeman/HNG/devops/stage2/.env}"
COMPOSE_FILE="${COMPOSE_FILE:-/home/freeman/HNG/devops/stage2/docker-compose.yml}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to get current active pool
get_current_pool() {
    if [ -f "$ENV_FILE" ]; then
        grep "^ACTIVE_POOL=" "$ENV_FILE" | cut -d'=' -f2 | tr -d '"' || echo "blue"
    else
        echo "blue"
    fi
}

# Function to update environment file
update_env_file() {
    local new_pool=$1
    
    if [ -f "$ENV_FILE" ]; then
        # Update existing file
        sed -i "s/^ACTIVE_POOL=.*/ACTIVE_POOL=$new_pool/" "$ENV_FILE"
    else
        error "Environment file not found: $ENV_FILE"
        return 1
    fi
}

# Function to reload nginx configuration
reload_nginx() {
    local new_pool=$1
    
    log "Reloading nginx with new configuration..."
    
    # Update environment variable in the nginx container and reload
    if docker exec nginx_lb sh -c "export ACTIVE_POOL=$new_pool && /usr/local/bin/reload.sh"; then
        success "nginx configuration reloaded successfully"
    else
        error "Failed to reload nginx configuration"
        return 1
    fi
}

# Function to verify the switch
verify_switch() {
    local expected_pool=$1
    local max_attempts=10
    local attempt=1
    
    log "Verifying switch to $expected_pool pool..."
    
    while [ $attempt -le $max_attempts ]; do
        local current_response=$(curl -s -D - http://localhost:8080/version -o /dev/null 2>/dev/null || echo "")
        local current_pool=$(echo "$current_response" | awk -F': *' '/^[Xx]-[Aa]pp-[Pp]ool:/{gsub(/\r/, "", $2); print tolower($2); exit}')
        
        if [ "$current_pool" = "$expected_pool" ]; then
            success "Switch verified: traffic is now routed to $expected_pool pool"
            return 0
        fi
        
        warn "Attempt $attempt: Still seeing pool '$current_pool', expected '$expected_pool'"
        sleep 1
        attempt=$((attempt + 1))
    done
    
    error "Switch verification failed after $max_attempts attempts"
    return 1
}

# Function to display current status
show_status() {
    local current_pool=$(get_current_pool)
    
    echo "==============================================="
    log "Blue/Green Deployment Status"
    echo "==============================================="
    echo "Environment file: $ENV_FILE"
    echo "Current active pool: $current_pool"
    
    # Test connectivity to nginx
    echo ""
    echo "Current nginx response:"
    local response=$(curl -s -D - http://localhost:8080/version -o /dev/null 2>/dev/null || echo "Connection failed")
    if [ "$response" != "Connection failed" ]; then
        local active_pool=$(echo "$response" | awk -F': *' '/^[Xx]-[Aa]pp-[Pp]ool:/{gsub(/\r/, "", $2); print tolower($2); exit}')
        local release_id=$(echo "$response" | awk -F': *' '/^[Xx]-[Rr]elease-[Ii]d:/{gsub(/\r/, "", $2); print $2; exit}')
        echo "  Active pool: $active_pool"
        echo "  Release ID: $release_id"
    else
        echo "  Cannot connect to nginx (http://localhost:8080)"
    fi
    
    # Test direct pool connectivity
    echo ""
    echo "Direct pool connectivity:"
    if curl -s http://localhost:8081/healthz > /dev/null 2>&1; then
        echo "  Blue pool (8081): ✓ healthy"
    else
        echo "  Blue pool (8081): ✗ unhealthy"
    fi
    
    if curl -s http://localhost:8082/healthz > /dev/null 2>&1; then
        echo "  Green pool (8082): ✓ healthy"
    else
        echo "  Green pool (8082): ✗ unhealthy"
    fi
    
    echo "==============================================="
}

# Function to perform the switch
switch_to() {
    local target_pool=$1
    local current_pool=$(get_current_pool)
    
    if [ "$target_pool" = "$current_pool" ]; then
        warn "Already using $target_pool pool"
        return 0
    fi
    
    log "Switching from $current_pool to $target_pool pool..."
    
    # Step 1: Update environment file
    log "Step 1: Updating environment file..."
    if ! update_env_file "$target_pool"; then
        error "Failed to update environment file"
        return 1
    fi
    
    # Step 2: Reload nginx
    log "Step 2: Reloading nginx configuration..."
    if ! reload_nginx "$target_pool"; then
        error "Failed to reload nginx"
        # Rollback
        update_env_file "$current_pool"
        return 1
    fi
    
    # Step 3: Verify the switch
    log "Step 3: Verifying switch..."
    if ! verify_switch "$target_pool"; then
        error "Switch verification failed"
        # Rollback
        update_env_file "$current_pool"
        reload_nginx "$current_pool"
        return 1
    fi
    
    success "Successfully switched to $target_pool pool"
    return 0
}

# Main function
main() {
    case "${1:-status}" in
        "blue")
            switch_to "blue"
            ;;
        "green")
            switch_to "green"
            ;;
        "toggle")
            local current_pool=$(get_current_pool)
            if [ "$current_pool" = "blue" ]; then
                switch_to "green"
            else
                switch_to "blue"
            fi
            ;;
        "status")
            show_status
            ;;
        "help"|*)
            echo "Usage: $0 <command>"
            echo ""
            echo "Commands:"
            echo "  blue      Switch to blue pool"
            echo "  green     Switch to green pool"
            echo "  toggle    Toggle between blue and green"
            echo "  status    Show current status"
            echo "  help      Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 blue     # Switch to blue pool"
            echo "  $0 green    # Switch to green pool"
            echo "  $0 toggle   # Toggle active pool"
            echo "  $0 status   # Show current status"
            ;;
    esac
}

main "$@"