#!/usr/bin/env bash
set -euo pipefail

# Chaos Testing Script
# Triggers and manages chaos testing for Blue/Green deployment

BLUE_URL="${BLUE_URL:-http://localhost:8081}"
GREEN_URL="${GREEN_URL:-http://localhost:8082}"

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

# Function to start chaos on a specific pool
start_chaos() {
    local pool=$1
    local mode=${2:-error}
    local url=""
    
    case $pool in
        "blue")
            url="$BLUE_URL"
            ;;
        "green")
            url="$GREEN_URL"
            ;;
        *)
            error "Invalid pool: $pool. Use 'blue' or 'green'"
            return 1
            ;;
    esac
    
    log "Starting chaos mode '$mode' on $pool pool..."
    
    if curl -s -X POST "$url/chaos/start?mode=$mode" > /dev/null; then
        success "Chaos started on $pool pool (mode: $mode)"
        warn "Pool $pool is now simulating failures"
    else
        error "Failed to start chaos on $pool pool"
        return 1
    fi
}

# Function to stop chaos on a specific pool
stop_chaos() {
    local pool=$1
    local url=""
    
    case $pool in
        "blue")
            url="$BLUE_URL"
            ;;
        "green")
            url="$GREEN_URL"
            ;;
        *)
            error "Invalid pool: $pool. Use 'blue' or 'green'"
            return 1
            ;;
    esac
    
    log "Stopping chaos on $pool pool..."
    
    if curl -s -X POST "$url/chaos/stop" > /dev/null; then
        success "Chaos stopped on $pool pool"
        log "Pool $pool is now healthy"
    else
        error "Failed to stop chaos on $pool pool"
        return 1
    fi
}

# Function to check health of both pools
check_health() {
    log "Checking health of both pools..."
    
    echo "Blue Pool Health:"
    if curl -s "$BLUE_URL/healthz" > /dev/null; then
        success "  Blue pool is healthy"
    else
        error "  Blue pool is unhealthy"
    fi
    
    echo "Green Pool Health:"
    if curl -s "$GREEN_URL/healthz" > /dev/null; then
        success "  Green pool is healthy"
    else
        error "  Green pool is unhealthy"
    fi
    
    echo ""
    echo "Pool Status:"
    echo "Blue version:"
    curl -s "$BLUE_URL/version" | head -20 2>/dev/null || echo "  Failed to get version"
    
    echo "Green version:"
    curl -s "$GREEN_URL/version" | head -20 2>/dev/null || echo "  Failed to get version"
}

# Function to run automated failover test
run_failover_test() {
    local active_pool=${1:-blue}
    local chaos_mode=${2:-error}
    
    log "Running automated failover test..."
    log "Active pool: $active_pool"
    log "Chaos mode: $chaos_mode"
    
    # Ensure both pools are healthy first
    log "Step 1: Ensuring both pools are healthy..."
    stop_chaos blue 2>/dev/null || true
    stop_chaos green 2>/dev/null || true
    sleep 2
    
    # Start the verification script in background
    log "Step 2: Starting continuous monitoring..."
    local script_dir="$(dirname "$0")"
    "$script_dir/failover_test.sh" --verbose --iterations 300 &
    local monitor_pid=$!
    
    # Wait a moment for monitoring to start
    sleep 3
    
    # Trigger chaos on the active pool
    log "Step 3: Triggering chaos on $active_pool pool..."
    start_chaos "$active_pool" "$chaos_mode"
    
    # Wait for the monitoring to complete
    log "Step 4: Waiting for monitoring to complete..."
    wait $monitor_pid
    local test_result=$?
    
    # Clean up - stop chaos
    log "Step 5: Cleaning up..."
    stop_chaos "$active_pool"
    
    if [ $test_result -eq 0 ]; then
        success "Automated failover test PASSED"
    else
        error "Automated failover test FAILED"
    fi
    
    return $test_result
}

# Main function
main() {
    case "${1:-help}" in
        "start")
            if [ $# -lt 2 ]; then
                error "Usage: $0 start <blue|green> [error|timeout]"
                exit 1
            fi
            start_chaos "$2" "${3:-error}"
            ;;
        "stop")
            if [ $# -lt 2 ]; then
                error "Usage: $0 stop <blue|green>"
                exit 1
            fi
            stop_chaos "$2"
            ;;
        "health")
            check_health
            ;;
        "test")
            run_failover_test "${2:-blue}" "${3:-error}"
            ;;
        "help"|*)
            echo "Usage: $0 <command> [arguments]"
            echo ""
            echo "Commands:"
            echo "  start <pool> [mode]   Start chaos on blue or green pool"
            echo "                        Modes: error (default), timeout"
            echo "  stop <pool>           Stop chaos on blue or green pool"
            echo "  health                Check health of both pools"
            echo "  test [pool] [mode]    Run automated failover test"
            echo "  help                  Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 start blue error   # Start error chaos on blue pool"
            echo "  $0 stop blue          # Stop chaos on blue pool"
            echo "  $0 health             # Check both pools"
            echo "  $0 test blue error    # Run full failover test"
            ;;
    esac
}

main "$@"