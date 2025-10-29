#!/bin/bash
# Quick diagnostic and fix script

echo "🔍 HNG Blue/Green Deployment Diagnostic"
echo "======================================="

echo "1. Checking container status..."
docker compose ps

echo -e "\n2. Checking application logs..."
echo "--- Blue App Logs ---"
docker compose logs app_blue | tail -10

echo -e "\n--- Green App Logs ---"
docker compose logs app_green | tail -10

echo -e "\n--- Nginx Logs ---"
docker compose logs nginx | tail -10

echo -e "\n3. Testing direct app connectivity..."
echo "Testing Blue app (port 8081):"
curl -f http://localhost:8081/healthz 2>/dev/null && echo "✅ Blue healthy" || echo "❌ Blue not responding"

echo "Testing Green app (port 8082):"
curl -f http://localhost:8082/healthz 2>/dev/null && echo "✅ Green healthy" || echo "❌ Green not responding"

echo -e "\n4. Checking internal container connectivity..."
echo "Blue container internal IP:"
docker inspect app_blue --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'

echo "Green container internal IP:"
docker inspect app_green --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'

echo -e "\n5. Testing internal nginx config..."
echo "Current nginx configuration:"
docker exec nginx_lb cat /etc/nginx/conf.d/default.conf | head -20

echo -e "\n6. Manual container restart if needed..."
read -p "Restart containers? (y/n): " restart
if [ "$restart" = "y" ]; then
    echo "Restarting containers..."
    docker compose restart app_blue app_green nginx
    sleep 15
    echo "Testing after restart:"
    curl -i http://localhost:8080/version
fi