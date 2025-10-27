#!/usr/bin/env bash
set -euo pipefail

# Blue/Green Failover Verification Script
# Tests automatic failover behavior and validates zero-downtime requirements

# Configuration
NGINX_URL="${NGINX_URL:-http://localhost:8080}"
ITERATIONS="${ITERATIONS:-200}"
DELAY="${DELAY:-0.05}"
MAX_REQUEST_TIME="${MAX_REQUEST_TIME:-6}"
REQUIRED_GREEN_PERCENTAGE="${REQUIRED_GREEN_PERCENTAGE:-95}"

# Counters
NON_200_COUNT=0
BLUE_COUNT=0
GREEN_COUNT=0
TIMEOUT_COUNT=0
TOTAL_REQUESTS=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
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

# Function to make a single request and parse response
make_request() {
    local iteration=$1
    local temp_file=$(mktemp)
    local exit_code=0
    
    # Make request with timeout
    curl -s -D "$temp_file" \
         --max-time "$MAX_REQUEST_TIME" \
         --connect-timeout 2 \
         --retry 0 \
         "$NGINX_URL/version" \
         -o /dev/null 2>/dev/null || exit_code=$?
    
    # Parse HTTP status code
    local http_code=""
    if [ -f "$temp_file" ]; then
        http_code=$(awk '/^HTTP/{print $2; exit}' "$temp_file" 2>/dev/null || echo "000")
    else
        http_code="000"
    fi
    
    # Parse X-App-Pool header
    local app_pool=""
    if [ -f "$temp_file" ]; then
        app_pool=$(awk -F': *' '/^[Xx]-[Aa]pp-[Pp]ool:/{gsub(/\r/, "", $2); print tolower($2); exit}' "$temp_file" 2>/dev/null || echo "")
    fi
    
    # Parse X-Release-Id header
    local release_id=""
    if [ -f "$temp_file" ]; then
        release_id=$(awk -F': *' '/^[Xx]-[Rr]elease-[Ii]d:/{gsub(/\r/, "", $2); print $2; exit}' "$temp_file" 2>/dev/null || echo "")
    fi
    
    # Clean up temp file
    rm -f "$temp_file"
    
    # Handle timeout/connection errors
    if [ $exit_code -ne 0 ]; then
        TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
        http_code="TIMEOUT"
    fi
    
    # Count responses
    TOTAL_REQUESTS=$((TOTAL_REQUESTS + 1))
    
    if [ "$http_code" != "200" ]; then
        NON_200_COUNT=$((NON_200_COUNT + 1))
        if [ "$VERBOSE" = "true" ]; then
            warn "Request $iteration: HTTP $http_code, Pool: $app_pool, Release: $release_id"
        fi
    else
        case "$app_pool" in
            "blue")
                BLUE_COUNT=$((BLUE_COUNT + 1))
                ;;
            "green")
                GREEN_COUNT=$((GREEN_COUNT + 1))
                ;;
            *)
                NON_200_COUNT=$((NON_200_COUNT + 1))
                if [ "$VERBOSE" = "true" ]; then
                    warn "Request $iteration: Missing or invalid X-App-Pool header: '$app_pool'"
                fi
                ;;
        esac
        
        if [ "$VERBOSE" = "true" ]; then
            echo "Request $iteration: HTTP $http_code, Pool: $app_pool, Release: $release_id"
        fi
    fi
}

# Function to display real-time progress
show_progress() {
    local current=$1
    local total=$2
    local percentage=$((current * 100 / total))
    local progress_bar=""
    
    # Create progress bar
    local filled=$((percentage / 2))
    local empty=$((50 - filled))
    
    for ((i=0; i<filled; i++)); do
        progress_bar+="█"
    done
    
    for ((i=0; i<empty; i++)); do
        progress_bar+="░"
    done
    
    printf "\r${BLUE}Progress:${NC} [%s] %d%% (%d/%d) | 200s: %d | Blue: %d | Green: %d | Errors: %d" \
           "$progress_bar" "$percentage" "$current" "$total" \
           $((TOTAL_REQUESTS - NON_200_COUNT)) "$BLUE_COUNT" "$GREEN_COUNT" "$NON_200_COUNT"
}

# Main execution function
main() {
    log "Starting Blue/Green failover verification"
    log "Target: $NGINX_URL/version"
    log "Iterations: $ITERATIONS"
    log "Request timeout: ${MAX_REQUEST_TIME}s"
    log "Required Green percentage after failover: ${REQUIRED_GREEN_PERCENTAGE}%"
    echo ""
    
    # Initial connectivity test
    log "Testing initial connectivity..."
    if ! curl -s --max-time 5 "$NGINX_URL/version" > /dev/null; then
        error "Cannot reach $NGINX_URL/version - ensure the service is running"
        exit 1
    fi
    success "Initial connectivity test passed"
    echo ""
    
    # Run the test iterations
    log "Running failover verification test..."
    
    for i in $(seq 1 "$ITERATIONS"); do
        make_request "$i"
        
        # Show progress every 10 requests or if verbose
        if [ $((i % 10)) -eq 0 ] || [ "$VERBOSE" = "true" ]; then
            show_progress "$i" "$ITERATIONS"
        fi
        
        # Brief delay between requests
        sleep "$DELAY"
    done
    
    # Final progress update
    show_progress "$ITERATIONS" "$ITERATIONS"
    echo ""
    echo ""
    
    # Calculate statistics
    local green_percentage=0
    if [ "$TOTAL_REQUESTS" -gt 0 ]; then
        green_percentage=$((GREEN_COUNT * 100 / TOTAL_REQUESTS))
    fi
    
    local success_rate=0
    if [ "$TOTAL_REQUESTS" -gt 0 ]; then
        success_rate=$(((TOTAL_REQUESTS - NON_200_COUNT) * 100 / TOTAL_REQUESTS))
    fi
    
    # Display results
    echo "==============================================="
    log "Failover Verification Results"
    echo "==============================================="
    echo "Total Requests:      $TOTAL_REQUESTS"
    echo "Successful (200):    $((TOTAL_REQUESTS - NON_200_COUNT)) (${success_rate}%)"
    echo "Failed (non-200):    $NON_200_COUNT"
    echo "Timeouts:            $TIMEOUT_COUNT"
    echo "Blue Responses:      $BLUE_COUNT"
    echo "Green Responses:     $GREEN_COUNT (${green_percentage}%)"
    echo "==============================================="
    
    # Validation
    local exit_code=0
    
    if [ "$NON_200_COUNT" -gt 0 ]; then
        error "FAIL: Found $NON_200_COUNT non-200 responses (requirement: 0)"
        exit_code=1
    else
        success "PASS: Zero non-200 responses"
    fi
    
    if [ "$green_percentage" -lt "$REQUIRED_GREEN_PERCENTAGE" ]; then
        error "FAIL: Green response percentage $green_percentage% < required ${REQUIRED_GREEN_PERCENTAGE}%"
        exit_code=2
    else
        success "PASS: Green response percentage $green_percentage% >= required ${REQUIRED_GREEN_PERCENTAGE}%"
    fi
    
    if [ "$exit_code" -eq 0 ]; then
        success "ALL TESTS PASSED: Zero-downtime failover verified"
    else
        error "TESTS FAILED: Failover requirements not met"
    fi
    
    return $exit_code
}

# Parse command line arguments
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -i|--iterations)
            ITERATIONS="$2"
            shift 2
            ;;
        -d|--delay)
            DELAY="$2"
            shift 2
            ;;
        -u|--url)
            NGINX_URL="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -v, --verbose          Enable verbose output"
            echo "  -i, --iterations NUM   Number of requests to make (default: 200)"
            echo "  -d, --delay SECONDS    Delay between requests (default: 0.05)"
            echo "  -u, --url URL          Target URL (default: http://localhost:8080)"
            echo "  -h, --help             Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  NGINX_URL              Target URL"
            echo "  ITERATIONS             Number of requests"
            echo "  DELAY                  Delay between requests"
            echo "  MAX_REQUEST_TIME       Request timeout in seconds"
            echo "  REQUIRED_GREEN_PERCENTAGE  Minimum green percentage after failover"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Execute main function
main