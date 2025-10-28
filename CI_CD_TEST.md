# HNG DevOps Stage 2 - CI/CD Test

This commit tests the automated CI/CD pipeline.

System Status: ✅ Ready for HNG submission

## Repository Contents

Essential files for HNG task:

- ✅ docker-compose.yml
- ✅ .env.example
- ✅ README.md
- ✅ nginx/ (config templates)
- ✅ DECISION.md
- ✅ .github/workflows/ (CI/CD)
- ✅ scripts/ (verification tools)

## Testing Instructions

1. The CI/CD pipeline will automatically:

   - Start the Blue/Green system
   - Run comprehensive failover tests
   - Verify zero-downtime requirements
   - Generate test reports

2. Manual testing:
   ```bash
   docker compose up -d
   curl http://localhost:8080/
   ./scripts/toggle.sh status
   ```

## Production Deployment

Replace the demo images in .env:

```bash
BLUE_IMAGE=your-registry/nodejs-app:blue-tag
GREEN_IMAGE=your-registry/nodejs-app:green-tag
```
