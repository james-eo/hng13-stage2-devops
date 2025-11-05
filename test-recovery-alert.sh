#!/bin/bash
# Test script for recovery alert functionality

set -e

echo "=================================================="
echo "Testing Recovery Alert Implementation"
echo "=================================================="
echo ""

echo "✅ Step 1: Ensure services are running"
docker start app_blue app_green 2>/dev/null || true
sleep 3
curl -s http://localhost:8080/version > /dev/null && echo "   Services healthy" || echo "   Services not ready"
echo ""

echo "🔄 Step 2: Create clean state with successful requests"
echo "   Generating 100 successful requests..."
for i in {1..100}; do
  curl -s http://localhost:8080/version > /dev/null 2>&1
done
echo "   ✓ Clean baseline established"
echo ""

echo "❌ Step 3: Stop services to create error state"
docker stop app_blue app_green > /dev/null
echo "   ✓ Services stopped"
sleep 2
echo ""

echo "🚨 Step 4: Generate errors to trigger alert"
echo "   Generating 80 error requests..."
for i in {1..80}; do
  curl -s http://localhost:8080/version > /dev/null 2>&1
done
echo "   ✓ Error state created (check Slack for error alert)"
sleep 5
echo ""

echo "✅ Step 5: Recover services"
docker start app_blue app_green > /dev/null
echo "   ✓ Services started"
sleep 5
echo ""

echo "🔄 Step 6: Generate successful requests to trigger recovery"
echo "   Generating 250 successful requests to flush error window..."
for i in {1..250}; do
  curl -s http://localhost:8080/version > /dev/null 2>&1
  if [ $((i % 50)) -eq 0 ]; then
    echo "   Progress: $i/250"
  fi
done
echo "   ✓ Recovery requests sent"
sleep 3
echo ""

echo "=================================================="
echo "📊 Results:"
echo "=================================================="
echo ""
echo "Check your Slack channel for:"
echo "  1. 🚨 High Error Rate alert (sent during Step 4)"
echo "  2. ✅ Service Recovery alert (sent during Step 6)"
echo ""
echo "View watcher logs:"
echo "  docker compose logs alert_watcher --tail=20"
echo ""
echo "=================================================="
