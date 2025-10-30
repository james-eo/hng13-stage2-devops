# Blue/Green Deployment Runbook

## HNG DevOps Stage 3 - Observability & Alerts

### Overview

This runbook provides operational guidance for responding to alerts from the Blue/Green deployment monitoring system. The alert watcher monitors nginx logs and sends notifications to Slack when critical events occur.

---

## Alert Types & Response Procedures

### 🔄 Failover Detected Alert

**When:** Active pool changes from Blue→Green or Green→Blue

**Example Alert:**

```
🔄 Blue/Green Failover Detected
Pool Change: Blue → Green
Timestamp: 2025-10-31 15:30:45 UTC
Action Required: Check health of blue pool containers
```

**Immediate Actions:**

1. **Acknowledge the alert** - Failover is working as designed
2. **Check the health of the failed pool:**

   ```bash
   # Check container status
   docker compose ps

   # Check logs of the failed pool
   docker compose logs app_blue  # if blue failed
   docker compose logs app_green # if green failed

   # Check direct pool connectivity
   curl http://localhost:8081/healthz  # blue
   curl http://localhost:8082/healthz  # green
   ```

3. **Verify traffic is routing correctly:**
   ```bash
   # Should show the new active pool
   curl -i http://localhost:8080/version
   ```

**Root Cause Investigation:**

- Check application logs for errors or crashes
- Monitor resource usage (CPU, memory, disk)
- Look for recent deployments or changes
- Check upstream dependencies

**Recovery Actions:**

- If the failed pool is healthy again, consider switching back:
  ```bash
  ./scripts/toggle.sh blue  # or green
  ```
- If issues persist, investigate application code or infrastructure

---

### 🚨 High Error Rate Alert

**When:** Error rate exceeds threshold (default: 2% over 200 requests)

**Example Alert:**

```
🚨 High Error Rate Detected
Error Rate: 5.2%
Window: 12/200 requests
Timestamp: 2025-10-31 15:35:20 UTC
Action Required: Inspect upstream logs and consider pool toggle
```

**Immediate Actions:**

1. **Check current system status:**

   ```bash
   # Verify which pool is active
   ./scripts/toggle.sh status

   # Check both pools directly
   curl http://localhost:8081/version
   curl http://localhost:8082/version
   ```

2. **Examine error patterns:**

   ```bash
   # Check nginx error logs
   docker compose logs nginx | tail -50

   # Check application logs
   docker compose logs app_blue | tail -50
   docker compose logs app_green | tail -50
   ```

3. **Consider immediate mitigation:**
   ```bash
   # If one pool is healthy, switch to it
   ./scripts/toggle.sh green  # if blue is problematic
   ./scripts/toggle.sh blue   # if green is problematic
   ```

**Root Cause Investigation:**

- Analyze error types (5xx vs application errors)
- Check application dependencies (databases, APIs)
- Monitor system resources
- Review recent changes or deployments

**Prevention:**

- Implement better health checks
- Add circuit breakers for dependencies
- Monitor application metrics more closely

---

### ✅ Service Recovery Alert

**When:** System returns to normal operation

**Example Alert:**

```
✅ Service Recovery Detected
Status: Blue pool is serving traffic normally
Timestamp: 2025-10-31 15:40:15 UTC
```

**Actions:**

1. **Verify recovery is stable:**

   ```bash
   # Monitor for 5-10 minutes
   watch -n 30 'curl -s http://localhost:8080/version | jq'
   ```

2. **Document the incident:**
   - Record what happened
   - Note resolution steps
   - Update monitoring if needed

---

## Maintenance Procedures

### Planned Pool Switches

When performing planned maintenance, you can temporarily suppress alerts:

1. **Manual Pool Toggle:**

   ```bash
   # Switch pools manually
   ./scripts/toggle.sh green

   # Perform maintenance on blue
   # Switch back when ready
   ./scripts/toggle.sh blue
   ```

2. **Alert Suppression:**
   The system has built-in cooldowns (default: 5 minutes) to prevent alert spam during maintenance windows.

### Emergency Procedures

#### Complete Service Outage

```bash
# 1. Check all containers
docker compose ps

# 2. Restart failed services
docker compose restart app_blue app_green nginx

# 3. Check logs for errors
docker compose logs

# 4. If issues persist, rebuild
docker compose down
docker compose up -d
```

#### Database/Dependency Issues

```bash
# 1. Check application logs for connection errors
docker compose logs | grep -i "error\|connection\|timeout"

# 2. Verify external dependencies
# (Check database connectivity, API endpoints, etc.)

# 3. Consider graceful degradation
# (Switch to pool with better dependency connectivity)
```

---

## Monitoring & Observability

### Log Locations

- **Nginx Access Logs:** `/shared/logs/nginx_observability.log`
- **Container Logs:** `docker compose logs [service_name]`
- **Alert Watcher Logs:** `docker compose logs alert_watcher`

### Log Format

Nginx logs include structured JSON with these fields:

```json
{
  "timestamp": "2025-10-31T15:30:45+00:00",
  "client_ip": "192.168.1.100",
  "method": "GET",
  "uri": "/version",
  "status": 200,
  "pool": "blue",
  "release": "blue-release-v1.0.0",
  "upstream_status": "200",
  "upstream_addr": "172.20.0.3:8080",
  "request_time": 0.023,
  "upstream_response_time": "0.021"
}
```

### Key Metrics to Monitor

- **Pool Distribution:** % of requests served by each pool
- **Response Times:** request_time and upstream_response_time
- **Error Rates:** Status codes 4xx and 5xx
- **Failover Frequency:** How often pools switch

---

## Configuration Reference

### Environment Variables

| Variable               | Default    | Description                             |
| ---------------------- | ---------- | --------------------------------------- |
| `SLACK_WEBHOOK_URL`    | _required_ | Slack incoming webhook URL              |
| `ERROR_RATE_THRESHOLD` | 2          | Error rate percentage to trigger alerts |
| `WINDOW_SIZE`          | 200        | Number of requests in sliding window    |
| `ALERT_COOLDOWN_SEC`   | 300        | Seconds between repeated alerts         |
| `ACTIVE_POOL`          | blue       | Initially active pool                   |

### Testing Alerts

```bash
# Test failover alert
curl -X POST http://localhost:8081/chaos/start?mode=error
sleep 10
curl http://localhost:8080/version  # Should trigger failover

# Test error rate alert
# (Generate many 5xx responses)
for i in {1..50}; do
  curl http://localhost:8081/chaos/start?mode=error
  curl http://localhost:8080/version
done

# Stop chaos testing
curl -X POST http://localhost:8081/chaos/stop
```

---

## Troubleshooting

### Alert Watcher Not Working

```bash
# Check watcher container status
docker compose ps alert_watcher

# Check watcher logs
docker compose logs alert_watcher

# Verify log file exists
docker exec alert_watcher ls -la /shared/logs/

# Test Slack webhook manually
curl -X POST -H 'Content-type: application/json' \
  --data '{"text":"Test message"}' \
  $SLACK_WEBHOOK_URL
```

### No Alerts Received

1. **Check Slack webhook URL** is correct
2. **Verify alert cooldown** hasn't suppressed alerts
3. **Check log parsing** in watcher logs
4. **Ensure shared volume** is mounted correctly

### False Positive Alerts

1. **Adjust thresholds** in .env file
2. **Increase cooldown periods** for noisy alerts
3. **Review log parsing logic** for edge cases

---

## Contact Information

**Primary On-Call:** DevOps Team  
**Slack Channel:** #devops-alerts  
**Escalation:** Engineering Manager

**Emergency Contacts:**

- DevOps Lead: `@devops-lead`
- Platform Engineer: `@platform-eng`
- SRE Team: `@sre-team`

---

_Last Updated: October 31, 2025_  
_Version: 1.0_
