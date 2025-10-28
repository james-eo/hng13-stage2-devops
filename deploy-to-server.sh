#!/bin/bash
# Quick DigitalOcean deployment script

echo "🚀 HNG DevOps Stage 2 - Quick Server Deployment"
echo "=============================================="

# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Install Docker Compose
sudo apt install docker-compose-plugin -y

# Clone your repository
git clone https://github.com/james-eo/hng13-stage2-devops.git
cd hng13-stage2-devops

# Setup environment
cp .env.example .env

# Update .env for production
cat > .env << EOF
# Blue/Green deployment configuration - PRODUCTION
BLUE_IMAGE=nginxdemos/hello:plain-text
GREEN_IMAGE=nginxdemos/hello:plain-text
ACTIVE_POOL=blue
RELEASE_ID_BLUE=blue-prod-v1.0.0
RELEASE_ID_GREEN=green-prod-v1.0.0
PORT=80
EOF

# Start the system
docker compose up -d

# Show status
echo ""
echo "✅ Deployment Complete!"
echo "Your Blue/Green system is running at:"
echo "  - http://$(curl -s ifconfig.me):8080 (nginx load balancer)"
echo "  - http://$(curl -s ifconfig.me):8081 (blue direct)"
echo "  - http://$(curl -s ifconfig.me):8082 (green direct)"
echo ""
echo "Test with:"
echo "  curl http://$(curl -s ifconfig.me):8080/version"
echo ""
echo "Your IP Address for HNG submission: $(curl -s ifconfig.me)"