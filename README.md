# Blue/Green Deployment with Nginx Load Balancer + Observability

A zero-downtime Blue/Green deployment system using nginx for automatic failover and manual traffic switching between identical Node.js application instances. **Extended for HNG Stage 3** with comprehensive observability, real-time log monitoring, and automated Slack alerting.

## 🚀 Quick Start

```bash
# 1. Copy environment template
cp .env.example .env

# 2. Update .env with your container images
# Edit BLUE_IMAGE and GREEN_IMAGE with actual image references

# 3. Start the deployment
docker-compose up -d

# 4. Verify deployment
curl http://localhost:8080/version
```

## 📋 Requirements

- Docker & Docker Compose
- curl (for testing)
- bash (for scripts)

## 🏗️ Architecture

```
┌─────────────────┐    ┌──────────────┐    ┌─────────────────┐
│   Load Balancer │    │              │    │   App (Blue)    │
│     (nginx)     │◄───┤   Primary    │◄───┤   Port: 8081    │
│   Port: 8080    │    │              │    │                 │
└─────────────────┘    │              │    └─────────────────┘
                       │   Upstream   │
                       │              │    ┌─────────────────┐
                       │              │    │   App (Green)   │
                       │   Backup     │◄───┤   Port: 8082    │
                       │              │    │                 │
                       └──────────────┘    └─────────────────┘
```

### Components

1. **nginx Load Balancer** (Port 8080) - Public endpoint with intelligent routing
2. **Blue Application** (Port 8081) - Primary application instance
3. **Green Application** (Port 8082) - Backup application instance

## 🔧 Configuration

### Environment Variables

All configuration is managed through environment variables defined in `.env`:

| Variable           | Description                               | Example                |
| ------------------ | ----------------------------------------- | ---------------------- |
| `BLUE_IMAGE`       | Container image for blue deployment       | `myregistry/app:blue`  |
| `GREEN_IMAGE`      | Container image for green deployment      | `myregistry/app:green` |
| `ACTIVE_POOL`      | Currently active pool (`blue` or `green`) | `blue`                 |
| `RELEASE_ID_BLUE`  | Release identifier for blue deployment    | `blue-v1.2.3`          |
| `RELEASE_ID_GREEN` | Release identifier for green deployment   | `green-v1.2.4`         |
| `PORT`             | Application port inside containers        | `8080`                 |

### nginx Configuration

The nginx configuration is dynamically generated based on the `ACTIVE_POOL` setting:

- **Primary server**: Receives all traffic normally
- **Backup server**: Only receives traffic when primary fails
- **Failover timing**: 1 second connection timeout, 3 second read timeout
- **Health checking**: Passive health checks with `max_fails=1` and `fail_timeout=2s`

## 🎯 Usage

### Starting the System

```bash
# Start all services
docker-compose up -d

# Check service status
docker-compose ps

# View logs
docker-compose logs -f nginx
```

### Testing Endpoints

```bash
# Main application endpoint (via nginx)
curl -i http://localhost:8080/version

# Direct blue instance
curl -i http://localhost:8081/version

# Direct green instance
curl -i http://localhost:8082/version

# Health checks
curl http://localhost:8081/healthz
curl http://localhost:8082/healthz
```

### Manual Pool Switching

```bash
# Switch to green pool
./scripts/toggle.sh green

# Switch to blue pool
./scripts/toggle.sh blue

# Toggle between pools
./scripts/toggle.sh toggle

# Check current status
./scripts/toggle.sh status
```

### Chaos Testing

```bash
# Start chaos testing on blue pool
./scripts/chaos.sh start blue error

# Stop chaos testing
./scripts/chaos.sh stop blue

# Check pool health
./scripts/chaos.sh health

# Run automated failover test
./scripts/chaos.sh test blue error
```

### Failover Verification

```bash
# Run comprehensive failover test
./scripts/failover_test.sh

# Run with verbose output
./scripts/failover_test.sh --verbose

# Run with custom parameters
./scripts/failover_test.sh --iterations 500 --delay 0.02
```

## 🔬 Testing Scenarios

### Scenario 1: Automatic Failover

1. Ensure blue is active: `./scripts/toggle.sh blue`
2. Start continuous monitoring: `./scripts/failover_test.sh --verbose &`
3. Trigger chaos on blue: `./scripts/chaos.sh start blue error`
4. Observe automatic switch to green pool
5. Stop chaos: `./scripts/chaos.sh stop blue`

Expected result: Zero non-200 responses, ≥95% green responses during failure

### Scenario 2: Manual Pool Switch

1. Check current pool: `./scripts/toggle.sh status`
2. Switch pools: `./scripts/toggle.sh toggle`
3. Verify switch: `curl -i http://localhost:8080/version`

Expected result: X-App-Pool header reflects new active pool

### Scenario 3: Full Automated Test

```bash
# Run complete failover verification
./scripts/chaos.sh test blue error
```

Expected result: All tests pass with zero failed requests

## 📊 Response Headers

The application returns these headers which nginx forwards unchanged:

- `X-App-Pool`: Identifies which pool served the request (`blue` or `green`)
- `X-Release-Id`: Release identifier for the serving application

Example response:

```
HTTP/1.1 200 OK
X-App-Pool: blue
X-Release-Id: blue-v1.2.3
Content-Type: application/json

{"version": "1.2.3", "pool": "blue"}
```

## 🚨 Monitoring & Troubleshooting

### Health Check Endpoints

```bash
# nginx health
curl http://localhost:8080/nginx-health

# nginx status
curl http://localhost:8080/nginx-status

# Application health
curl http://localhost:8081/healthz  # Blue
curl http://localhost:8082/healthz  # Green
```

### Log Monitoring

```bash
# All logs
docker-compose logs -f

# nginx specific
docker-compose logs -f nginx

# Application logs
docker-compose logs -f app_blue
docker-compose logs -f app_green
```

### Common Issues

1. **503 Service Unavailable**: Both application instances are down

   - Check: `docker-compose ps`
   - Fix: `docker-compose restart app_blue app_green`

2. **Slow failover**: nginx timeouts too generous

   - Check nginx configuration in container
   - Verify `max_fails` and `fail_timeout` settings

3. **Headers not forwarded**: Missing proxy_pass_header directives
   - Check nginx config includes `proxy_pass_header X-App-Pool`

## 🔄 CI/CD Integration

The system includes GitHub Actions workflow for automated verification:

### Workflow Triggers

- Push to main/develop branches
- Pull requests
- Manual dispatch with custom images

### Environment Variable Injection

For CI/grader systems, set these environment variables:

```bash
export BLUE_IMAGE="your-registry/app:blue-tag"
export GREEN_IMAGE="your-registry/app:green-tag"
export RELEASE_ID_BLUE="blue-release-id"
export RELEASE_ID_GREEN="green-release-id"
docker-compose up -d
```

### Verification Steps

1. Service startup verification
2. Baseline connectivity test
3. Automatic failover test
4. Manual toggle test
5. Log collection

## 📁 Project Structure

```
.
├── docker-compose.yml          # Main orchestration file
├── .env.example               # Environment template
├── nginx/
│   ├── entrypoint.sh          # nginx configuration generator
│   └── reload.sh              # Runtime configuration reload
├── scripts/
│   ├── failover_test.sh       # Comprehensive failover testing
│   ├── chaos.sh               # Chaos engineering utilities
│   └── toggle.sh              # Manual pool switching
├── .github/workflows/
│   └── verification.yml       # CI/CD pipeline
└── README.md                  # This file
```

## 🎯 Performance Characteristics

- **Failover time**: < 2 seconds (with default timeouts)
- **Request timeout**: 6 seconds maximum per request
- **Zero downtime**: No failed requests during normal failover
- **Throughput**: Limited by application performance, not nginx

## 🔐 Security Considerations

- Rate limiting: 100 requests/second with burst of 20
- Security headers: X-Frame-Options, X-Content-Type-Options
- Network isolation: Docker bridge network
- No sensitive data in environment variables

## 📚 References

- [nginx upstream module](http://nginx.org/en/docs/http/ngx_http_upstream_module.html)
- [Docker Compose networking](https://docs.docker.com/compose/networking/)
- [Blue-Green deployment patterns](https://martinfowler.com/bliki/BlueGreenDeployment.html)

## 📋 Part B Research

For the Backend.im CLI integration research, see [RESEARCH_PART_B.md](./RESEARCH_PART_B.md) which contains:

- Proposed architecture for Claude Code CLI integration
- Infrastructure setup recommendations
- Development workflow design
- Cost analysis and implementation roadmap
- Security considerations and deployment strategies

The research document will also be available as a Google Doc with public access for the HNG submission.

---

## 📊 Stage 3: Observability & Alerts

### Slack Alert System

The system now includes real-time monitoring with Slack notifications for:

- **🔄 Failover Events**: Automatic detection when traffic switches between Blue/Green pools
- **🚨 High Error Rates**: Alerts when 5xx error rate exceeds threshold (default: 2%)
- **✅ Recovery Events**: Notifications when service returns to normal

### Enhanced Logging

Nginx access logs now include structured JSON with observability data:

```json
{
  "timestamp": "2025-10-31T15:30:45+00:00",
  "pool": "blue",
  "release": "blue-release-v1.0.0",
  "upstream_status": "200",
  "upstream_addr": "172.20.0.3:8080",
  "request_time": 0.023,
  "upstream_response_time": "0.021"
}
```

### Alert Configuration

Configure alerts via environment variables in `.env`:

```bash
# Slack webhook URL (required)
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK

# Alert thresholds and timing
ERROR_RATE_THRESHOLD=2        # Error rate % to trigger alerts
WINDOW_SIZE=200               # Requests in sliding window
ALERT_COOLDOWN_SEC=300        # Seconds between repeated alerts
```

### Testing Alerts

```bash
# Test failover alert
curl -X POST http://localhost:8081/chaos/start?mode=error
sleep 10
curl http://localhost:8080/version  # Should trigger Slack alert

# Test error rate alert
for i in {1..50}; do
  curl http://localhost:8080/version
done

# Stop chaos
curl -X POST http://localhost:8081/chaos/stop
```

### Viewing Logs

```bash
# View structured nginx logs
docker exec nginx_lb tail -f /shared/logs/nginx_observability.log

# View alert watcher logs
docker compose logs alert_watcher

# View all container logs
docker compose logs -f
```

For detailed operational guidance, see [runbook.md](./runbook.md).

---

**Note**: This implementation prioritizes zero-downtime failover and operational simplicity while maintaining production-ready reliability and monitoring capabilities.
