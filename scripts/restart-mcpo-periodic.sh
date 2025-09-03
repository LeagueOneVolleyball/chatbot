#!/bin/bash

set -e

echo "Periodic MCPO Restart - $(date)"
echo "========================================="

PROJECT_ID="comp-tool-poc-lovb"
ZONE="us-central1-a"
INSTANCE_NAME="openwebui-mcpo"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}[INFO]${NC} Restarting MCPO service to refresh Snowflake authentication..."

# Restart only the MCPO service
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command='cd /app && sudo docker-compose restart mcpo-tools' || {
    echo -e "${RED}[ERROR]${NC} Failed to restart MCPO service"
    exit 1
}

echo -e "${GREEN}[SUCCESS]${NC} MCPO service restarted successfully at $(date)"

# Optional: Test the service is responding
echo -e "${YELLOW}[INFO]${NC} Testing MCPO service health..."
sleep 10

# Check if service is responding
EXTERNAL_IP=$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://$EXTERNAL_IP:8001/docs" || echo "000")

if [ "$HTTP_STATUS" = "200" ]; then
    echo -e "${GREEN}[SUCCESS]${NC} MCPO service is healthy and responding"
else
    echo -e "${YELLOW}[WARN]${NC} MCPO service returned status: $HTTP_STATUS (may still be starting up)"
fi

echo "========================================="
echo "MCPO restart completed at $(date)" 