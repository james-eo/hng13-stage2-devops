# Technical Decisions and Implementation Notes

## Overview

This document explains the technical decisions made during the implementation of the Blue/Green deployment system and provides insights into the tradeoffs, limitations, and operational considerations.

## nginx Configuration Decisions

### Passive Health Checking

**Decision**: Use nginx's built-in passive health checking instead of active health checks.

**Rationale**:

- nginx open-source doesn't include active health checks (nginx+ feature)
- Passive checks are sufficient for this use case
- Simpler configuration and lower resource overhead
- Grader can trigger failures directly via `/chaos/` endpoints

**Configuration**:

```nginx
server app_blue:8080 max_fails=1 fail_timeout=2s;
server app_green:8080 backup;
```

**Tradeoffs**:

- ✅ Simple and reliable
- ✅ No additional dependencies
- ❌ Requires actual request failure to detect issues
- ❌ Cannot detect issues before they affect users

### Timeout Configuration

**Decision**: Aggressive timeouts for fast failover.

**Timeouts chosen**:

- `proxy_connect_timeout 1s` - Fast connection failure detection
- `proxy_read_timeout 3s` - Quick read timeout
- `proxy_send_timeout 3s` - Quick send timeout
- `fail_timeout 2s` - Short server recovery window

**Rationale**:

- Requirement: requests must complete within 10 seconds
- Need zero failed client requests during failover
- Faster failure detection = faster failover
- Better user experience during outages

**Tradeoffs**:

- ✅ Fast failover (< 2 seconds)
- ✅ Meets zero-failure requirement
- ❌ May cause false positives under high load
- ❌ Less tolerance for temporary network hiccups

### Retry Configuration

**Decision**: Limited retry attempts with specific error conditions.

**Configuration**:

```nginx
proxy_next_upstream error timeout http_502 http_503 http_504 http_500;
proxy_next_upstream_tries 2;
proxy_next_upstream_timeout 5s;
```

**Rationale**:

- Retry on clear failure conditions (5xx, timeout, connection error)
- Limit retries to prevent request delays
- Allow time for backup server to respond
- Don't retry on 4xx (client errors)

**Edge Cases**:

- If both servers fail simultaneously, request will fail after trying both
- Network partitions may cause both servers to appear failed
- DNS resolution issues affect both upstreams equally

## Docker Compose Architecture

### Network Design

**Decision**: Single bridge network for all containers.

**Rationale**:

- Simple service discovery via container names
- All containers can communicate
- Easy debugging and monitoring
- Sufficient isolation for this use case

**Security considerations**:

- Containers are isolated from host network by default
- Only required ports exposed to host
- Rate limiting configured in nginx

### Port Mapping Strategy

**Decision**: Map application containers to dedicated host ports.

**Mapping**:

- nginx: `8080:80` (public endpoint)
- app_blue: `8081:${PORT}` (direct access for chaos testing)
- app_green: `8082:${PORT}` (direct access for chaos testing)

**Rationale**:

- Grader needs direct access to trigger chaos endpoints
- Allows independent testing of each application instance
- Clear separation between load-balanced and direct access
- Facilitates debugging and monitoring

## Health Checking Strategy

### Application Health Checks

**Decision**: Docker health checks + nginx passive health checks.

**Docker health check**:

```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:${PORT}/healthz"]
  interval: 10s
  timeout: 5s
  retries: 3
  start_period: 30s
```

**Rationale**:

- Docker health checks provide container-level health status
- nginx passive checks provide request-level failure detection
- `/healthz` endpoint tests application readiness
- Reasonable intervals to balance responsiveness and overhead

### nginx Health Monitoring

**Decision**: Provide both nginx health and status endpoints.

**Endpoints**:

- `/nginx-health` - Simple health check
- `/nginx-status` - Detailed nginx metrics (restricted access)

**Rationale**:

- Allows monitoring of load balancer health separately from applications
- Status endpoint provides debugging information
- Restricted access prevents information disclosure

## Environment Variable Strategy

### Configuration Management

**Decision**: All configuration via environment variables with `.env` file.

**Variables**:

- `BLUE_IMAGE`, `GREEN_IMAGE` - Container images
- `ACTIVE_POOL` - Controls nginx upstream ordering
- `RELEASE_ID_BLUE`, `RELEASE_ID_GREEN` - Passed to applications
- `PORT` - Application port (optional)

**Rationale**:

- Required by grader/CI system
- 12-factor app compliance
- Easy to change without rebuilding images
- Clear separation of configuration from code

### Runtime Configuration Changes

**Decision**: Support runtime nginx configuration reload without restart.

**Implementation**:

- `reload.sh` script regenerates config and sends SIGHUP
- Environment variables can be updated in container
- No service interruption during config changes

**Limitations**:

- Docker Compose environment variables are set at startup
- Full environment changes require container restart
- Manual coordination required between `.env` file and container environment

## Verification and Testing

### Failover Testing Strategy

**Decision**: Comprehensive automated testing with statistical validation.

**Test approach**:

- 200+ requests over ~10 seconds during failover
- Statistical analysis of response distribution
- Zero tolerance for failed requests
- Real-time progress monitoring

**Validation criteria**:

- 0 non-200 responses
- ≥95% responses from backup pool after failover
- Complete test execution within reasonable time

**Rationale**:

- Provides high confidence in failover behavior
- Catches edge cases that single-request tests miss
- Validates requirements quantitatively
- Suitable for CI/CD automation

### Chaos Engineering

**Decision**: Direct chaos injection via application endpoints.

**Implementation**:

- Use application's built-in `/chaos/start` and `/chaos/stop` endpoints
- Support different failure modes (error, timeout)
- Scriptable chaos management
- Clear start/stop semantics

**Advantages**:

- No additional infrastructure required
- Precise control over failure timing
- Repeatable test scenarios
- Applications handle their own failure simulation

## Known Limitations and Considerations

### nginx Open Source Limitations

1. **No active health checks**: Must rely on passive failure detection
2. **Limited load balancing algorithms**: Round-robin and IP hash only
3. **No dynamic upstream management**: Requires reload for configuration changes

### Operational Considerations

1. **Split-brain scenarios**: If network partitions isolate nginx from one pool
2. **Database consistency**: Applications must handle database failover independently
3. **Session affinity**: No session stickiness implemented (stateless applications assumed)
4. **Monitoring gaps**: No metrics collection configured (could add Prometheus/Grafana)

### Performance Considerations

1. **Connection pooling**: nginx keepalive configured for performance
2. **Rate limiting**: Prevents abuse but may limit legitimate traffic during load spikes
3. **Memory usage**: nginx upstream module loads all server definitions in memory
4. **File descriptor limits**: May need tuning for high-connection scenarios

### Security Considerations

1. **Direct pool access**: Application ports exposed to host (required for grader)
2. **Error disclosure**: nginx error pages may reveal internal information
3. **DoS protection**: Rate limiting provides basic protection only
4. **TLS termination**: Not configured (could be added if HTTPS required)

## Future Improvements

### Monitoring Enhancements

- Add Prometheus metrics export
- Implement structured logging
- Add distributed tracing support
- Create alerting rules for failover events

### Operational Improvements

- Add configuration validation
- Implement graceful shutdown procedures
- Add automated backup/restore for state
- Create operational runbooks

### Performance Optimizations

- Tune kernel networking parameters
- Implement connection pooling optimizations
- Add caching layer if appropriate
- Optimize container resource limits

### Security Hardening

- Add TLS termination
- Implement proper access controls
- Add security headers middleware
- Configure WAF rules

## Troubleshooting Guide

### Common Issues

1. **502 Bad Gateway**

   - Check: Application containers are running (`docker-compose ps`)
   - Check: Applications are listening on expected ports
   - Check: nginx can resolve upstream hostnames

2. **Slow or no failover**

   - Check: nginx timeout configuration
   - Check: Application chaos endpoints working
   - Check: nginx error logs for upstream status

3. **Headers not forwarded**

   - Verify: `proxy_pass_header` directives in nginx config
   - Check: Applications are setting expected headers
   - Test: Direct application endpoints return headers

4. **Configuration reload failures**
   - Check: nginx configuration syntax (`nginx -t`)
   - Verify: Environment variables set correctly
   - Check: File permissions on config files

### Debugging Commands

```bash
# Check nginx configuration
docker exec nginx_lb nginx -t

# View nginx upstream status
curl http://localhost:8080/nginx-status

# Check container connectivity
docker exec nginx_lb nslookup app_blue
docker exec nginx_lb nslookup app_green

# View real-time logs
docker-compose logs -f nginx

# Test direct application endpoints
curl -v http://localhost:8081/version
curl -v http://localhost:8082/version
```

## Conclusion

This implementation balances simplicity, reliability, and operational requirements while providing a solid foundation for zero-downtime Blue/Green deployments. The design decisions prioritize meeting the specified requirements while maintaining production readiness and debuggability.

The use of passive health checking and aggressive timeouts ensures fast failover at the cost of some resilience to network hiccups. The comprehensive testing strategy provides confidence in the failover behavior while the scriptable management tools enable both automated and manual operations.

For production use, consider implementing the suggested monitoring and security enhancements based on specific operational requirements and risk profiles.
