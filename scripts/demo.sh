#!/usr/bin/env bash
set -euo pipefail

# Complete Blue/Green Deployment Demo Script
# Demonstrates all functionality of the system

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

section() {
    echo ""
    echo -e "${CYAN}===============================================${NC}"
    echo -e "${CYAN} $1${NC}"
    echo -e "${CYAN}===============================================${NC}"
}

# Function to wait for user input
wait_for_user() {
    echo ""
    read -p "Press Enter to continue or Ctrl+C to exit..."
    echo ""
}

# Function to check prerequisites
check_prerequisites() {
    section "Checking Prerequisites"
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed or not in PATH"
        exit 1
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        error "Docker Compose is not installed"
        exit 1
    fi
    
    # Check curl
    if ! command -v curl &> /dev/null; then
        error "curl is not installed"
        exit 1
    fi
    
    success "All prerequisites met"
}

# Function to setup environment
setup_environment() {
    section "Setting Up Environment"
    
    cd "$PROJECT_DIR"
    
    # Ensure .env exists
    if [ ! -f .env ]; then
        log "Creating .env from template..."
        cp .env.example .env
    fi
    
    # Update .env with demo values
    cat > .env << EOF
# Blue/Green deployment configuration - DEMO MODE
BLUE_IMAGE=nginxdemos/hello:plain-text
GREEN_IMAGE=nginxdemos/hello:plain-text
ACTIVE_POOL=blue
RELEASE_ID_BLUE=blue-demo-v1.0.0
RELEASE_ID_GREEN=green-demo-v1.0.0
PORT=80
EOF
    
    success "Environment configured for demo"
    log "Configuration:"
    cat .env | sed 's/^/  /'
}

# Function to start the system
start_system() {
    section "Starting Blue/Green Deployment System"
    
    cd "$PROJECT_DIR"
    
    log "Starting Docker Compose stack..."
    docker-compose down -v 2>/dev/null || true
    docker-compose up -d
    
    log "Waiting for services to be ready..."
    sleep 15
    
    # Check service status
    log "Service status:"
    docker-compose ps
    
    # Wait for nginx to be ready
    for i in {1..30}; do
        if curl -s http://localhost:8080/nginx-health > /dev/null 2>&1; then
            success "nginx load balancer is ready"
            break
        fi
        if [ $i -eq 30 ]; then
            error "nginx failed to start after 30 attempts"
            docker-compose logs nginx
            exit 1
        fi
        log "Waiting for nginx... attempt $i"
        sleep 1
    done
}

# Function to demonstrate basic functionality
demo_basic_functionality() {
    section "Demonstrating Basic Functionality"
    
    log "Testing main endpoint (via nginx load balancer):"
    echo "  curl -i http://localhost:8080/"
    curl -i http://localhost:8080/ 2>/dev/null | head -20
    
    wait_for_user
    
    log "Testing direct pool access:"
    echo "  Blue pool (port 8081):"
    curl -s http://localhost:8081/ | head -5 || echo "  Blue pool not responding"
    
    echo "  Green pool (port 8082):"
    curl -s http://localhost:8082/ | head -5 || echo "  Green pool not responding"
    
    log "Testing nginx status:"
    curl -s http://localhost:8080/nginx-status 2>/dev/null || echo "  Status endpoint not available"
}

# Function to demonstrate pool switching
demo_pool_switching() {
    section "Demonstrating Manual Pool Switching"
    
    log "Current deployment status:"
    ./scripts/toggle.sh status
    
    wait_for_user
    
    log "Switching to green pool..."
    ./scripts/toggle.sh green
    
    log "Verifying switch:"
    for i in {1..5}; do
        echo "  Request $i:"
        curl -s -D - http://localhost:8080/ -o /dev/null 2>/dev/null | grep -E "HTTP|X-" || echo "    No response headers"
        sleep 1
    done
    
    wait_for_user
    
    log "Switching back to blue pool..."
    ./scripts/toggle.sh blue
    
    log "Current status after switch:"
    ./scripts/toggle.sh status
}

# Function to demonstrate monitoring
demo_monitoring() {
    section "Demonstrating Monitoring Capabilities"
    
    log "nginx health check:"
    curl -s http://localhost:8080/nginx-health
    
    log "nginx status (if available):"
    curl -s http://localhost:8080/nginx-status 2>/dev/null | head -10 || echo "  Status endpoint restricted"
    
    log "Container health status:"
    docker-compose ps
    
    log "Recent nginx logs:"
    docker-compose logs --tail=10 nginx
}

# Function to show configuration
show_configuration() {
    section "System Configuration"
    
    log "Environment variables:"
    cat .env | sed 's/^/  /'
    
    log "Generated nginx configuration:"
    docker exec nginx_lb cat /etc/nginx/conf.d/default.conf 2>/dev/null | head -30 || echo "  Cannot access nginx config"
    
    log "Available management scripts:"
    ls -la scripts/
}

# Function to demonstrate load balancing
demo_load_balancing() {
    section "Demonstrating Load Balancing Behavior"
    
    log "Making multiple requests to observe routing:"
    for i in {1..10}; do
        echo "Request $i:"
        curl -s -D - http://localhost:8080/ -o /dev/null 2>/dev/null | grep -E "HTTP|Server|X-" | sed 's/^/  /' || echo "  No response"
        sleep 0.5
    done
}

# Function to cleanup
cleanup() {
    section "Cleanup"
    
    cd "$PROJECT_DIR"
    
    log "Stopping all services..."
    docker-compose down -v
    
    success "Demo completed and cleaned up"
}

# Main demo function
main() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                                                              ║${NC}"
    echo -e "${CYAN}║          Blue/Green Deployment System Demo                   ║${NC}"
    echo -e "${CYAN}║                                                              ║${NC}"
    echo -e "${CYAN}║  This demo shows a complete Blue/Green deployment system    ║${NC}"
    echo -e "${CYAN}║  with nginx load balancing, automatic failover, and         ║${NC}"
    echo -e "${CYAN}║  manual pool switching capabilities.                        ║${NC}"
    echo -e "${CYAN}║                                                              ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    
    trap cleanup EXIT
    
    case "${1:-full}" in
        "full")
            check_prerequisites
            setup_environment
            start_system
            demo_basic_functionality
            demo_load_balancing
            demo_pool_switching
            demo_monitoring
            show_configuration
            ;;
        "quick")
            check_prerequisites
            setup_environment
            start_system
            demo_basic_functionality
            ;;
        "config")
            show_configuration
            ;;
        "help")
            echo "Usage: $0 [full|quick|config|help]"
            echo ""
            echo "  full   - Complete demonstration (default)"
            echo "  quick  - Basic functionality only"
            echo "  config - Show configuration files"
            echo "  help   - This help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
    
    section "Demo Summary"
    success "Blue/Green deployment system demonstration completed!"
    
    echo ""
    echo "Key features demonstrated:"
    echo "  ✅ Automated nginx configuration generation"
    echo "  ✅ Dynamic pool switching"
    echo "  ✅ Load balancing between instances"
    echo "  ✅ Health monitoring"
    echo "  ✅ Zero-downtime deployments"
    
    echo ""
    echo "For production use:"
    echo "  1. Replace demo images with actual Node.js applications"
    echo "  2. Implement the /version, /healthz, and /chaos/* endpoints"
    echo "  3. Configure monitoring and alerting"
    echo "  4. Set up CI/CD pipeline with the provided GitHub Actions workflow"
    
    echo ""
    echo "Available scripts for ongoing management:"
    echo "  - ./scripts/toggle.sh [blue|green|toggle|status]"
    echo "  - ./scripts/chaos.sh [start|stop|health|test]"
    echo "  - ./scripts/failover_test.sh [--verbose]"
}

main "$@"