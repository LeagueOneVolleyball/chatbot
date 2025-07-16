#!/bin/bash

set -e

echo "Uploading Application Files to GCP VM"
echo "======================================"

# Configuration
PROJECT_ID="comp-tool-poc-lovb"
ZONE="us-central1-a"
INSTANCE_NAME="openwebui-mcpo"

# Check if VM exists
if ! gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE >/dev/null 2>&1; then
    echo "ERROR: VM $INSTANCE_NAME not found in zone $ZONE"
    echo "   Run ./scripts/deploy-gcp-vm.sh first to create the VM"
    exit 1
fi

echo "Found VM: $INSTANCE_NAME"

# Create temporary directory with all files
echo "Preparing files for upload..."
TEMP_DIR=$(mktemp -d)
APP_DIR="$TEMP_DIR/app"

# Copy application files
mkdir -p "$APP_DIR"
cp docker-compose.yml "$APP_DIR/"
cp Dockerfile.mcpo "$APP_DIR/"
cp Dockerfile.openwebui "$APP_DIR/"
cp -r config "$APP_DIR/"
cp -r scripts "$APP_DIR/"
cp env.example "$APP_DIR/"
cp README.md "$APP_DIR/"

# Create environment file template for VM
cat > "$APP_DIR/.env.template" << 'ENV_EOF'
# OpenWebUI + MCP Servers Environment Configuration for GCP VM
# Copy this file to .env and fill in your actual values

# ============================================================================
# OpenAI Configuration
# ============================================================================
OPENAI_API_KEY=your-openai-api-key-here
OPENAI_API_BASE_URL=https://api.openai.com/v1

# ============================================================================
# WebUI Configuration
# ============================================================================
WEBUI_AUTH=false
WEBUI_SECRET_KEY=your-secret-key-here
WEBUI_URL=http://EXTERNAL_IP:8080

# ============================================================================
# Snowflake Configuration
# ============================================================================
SNOWFLAKE_ACCOUNT=UPNOBVJ-OK59235
SNOWFLAKE_USER=COMP_SERVICE_ACCOUNT
SNOWFLAKE_PRIVATE_KEY_PATH=/app/keys/comp_role_key.p8
SNOWFLAKE_PRIVATE_KEY_PASSPHRASE=your-private-key-passphrase
SNOWFLAKE_WAREHOUSE=COMP_ROLE_WH
SNOWFLAKE_DATABASE=SILVER_DB
SNOWFLAKE_SCHEMA=PUBLIC
SNOWFLAKE_ROLE=COMP_ROLE

# ============================================================================
# MCPO Configuration
# ============================================================================
MCPO_SNOWFLAKE_API_KEY=snowflake-secure-key-2024
MCPO_SNOWFLAKE_PORT=8001
MCPO_SNOWFLAKE_HOST=0.0.0.0

# ============================================================================
# User Permissions Configuration
# ============================================================================
USER_PERMISSIONS_WORKSPACE_TOOLS_ACCESS=true
ENV_EOF

# Update docker-compose.yml for VM deployment (remove local volume mounts)
cat > "$APP_DIR/docker-compose.yml" << 'COMPOSE_EOF'
version: '3.8'

services:
  # MCPO Tools Server (Multiple MCP Servers via MCPO)
  mcpo-tools:
    build:
      context: .
      dockerfile: Dockerfile.mcpo
    ports:
      - "8001:8001"
    environment:
      # Snowflake Configuration
      - SNOWFLAKE_ACCOUNT=${SNOWFLAKE_ACCOUNT}
      - SNOWFLAKE_USER=${SNOWFLAKE_USER}
      - SNOWFLAKE_PRIVATE_KEY_PATH=/app/keys/comp_role_key.p8
      - SNOWFLAKE_PRIVATE_KEY_PASSPHRASE=${SNOWFLAKE_PRIVATE_KEY_PASSPHRASE}
      - SNOWFLAKE_WAREHOUSE=${SNOWFLAKE_WAREHOUSE:-COMP_ROLE_WH}
      - SNOWFLAKE_DATABASE=${SNOWFLAKE_DATABASE:-SILVER_DB}
      - SNOWFLAKE_SCHEMA=${SNOWFLAKE_SCHEMA:-PUBLIC}
      - SNOWFLAKE_ROLE=${SNOWFLAKE_ROLE:-COMP_ROLE}
      # MCPO Configuration
      - MCPO_PORT=8001
      - MCPO_HOST=0.0.0.0
      - MCPO_API_KEY=${MCPO_SNOWFLAKE_API_KEY:-snowflake-secure-key-2024}
    volumes:
      - ./keys:/app/keys:ro
      - ./logs:/var/log/mcpo
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8001/docs"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    restart: unless-stopped
    networks:
      - openwebui-network
    command: >
      sh -c "
        echo 'Starting MCPO Tools Server on port 8001 with API key security...' &&
        uvx mcpo --host 0.0.0.0 --port 8001 --api-key '${MCPO_SNOWFLAKE_API_KEY:-snowflake-secure-key-2024}' -- uvx mcp-snowflake
      "

  # OpenWebUI with MCPO integration
  openwebui:
    build:
      context: .
      dockerfile: Dockerfile.openwebui
    ports:
      - "8080:8080"
    environment:
      # OpenAI Configuration
      - OPENAI_API_KEY=${OPENAI_API_KEY}
      - OPENAI_API_BASE_URL=${OPENAI_API_BASE_URL:-https://api.openai.com/v1}
      
      # WebUI Configuration
      - WEBUI_AUTH=${WEBUI_AUTH:-false}
      - WEBUI_SECRET_KEY=${WEBUI_SECRET_KEY}
      - WEBUI_URL=${WEBUI_URL:-http://localhost:8080}
      
      # User Permissions - Enable tool access for regular users
      - USER_PERMISSIONS_WORKSPACE_TOOLS_ACCESS=true
      
      # MCPO Server URLs with API Keys
      - MCPO_SNOWFLAKE_URL=http://mcpo-tools:8001
      - MCPO_SNOWFLAKE_API_KEY=${MCPO_SNOWFLAKE_API_KEY:-snowflake-secure-key-2024}
      - MCPO_SERVERS=snowflake:http://mcpo-tools:8001
      
      # OpenWebUI Data
      - DATA_DIR=/app/backend/data
      - UPLOAD_DIR=/app/backend/data/uploads
    volumes:
      - openwebui_data:/app/backend/data
      - ./logs:/var/log/openwebui
      - ./config:/app/config:ro
    depends_on:
      mcpo-tools:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    restart: unless-stopped
    networks:
      - openwebui-network

volumes:
  openwebui_data:
    driver: local

networks:
  openwebui-network:
    driver: bridge
COMPOSE_EOF

# Create deployment script for the VM
cat > "$APP_DIR/scripts/start-services.sh" << 'START_EOF'
#!/bin/bash

set -e

echo "Starting OpenWebUI + MCPO Services on GCP VM"
echo "============================================"

# Check if .env file exists
if [ ! -f .env ]; then
    echo "ERROR: .env file not found. Please create one based on .env.template"
    echo "   cp .env.template .env"
    echo "   vim .env  # Edit with your actual values"
    exit 1
fi

# Load environment variables
set -a
source .env
set +a

# Check if keys directory exists
if [ ! -d "keys" ]; then
    echo "ERROR: Keys directory not found. Please upload your Snowflake private key:"
    echo "   mkdir -p keys"
    echo "   # Upload your comp_role_key.p8 file to the keys/ directory"
    exit 1
fi

if [ ! -f "keys/comp_role_key.p8" ]; then
    echo "ERROR: Snowflake private key not found at keys/comp_role_key.p8"
    echo "   Please upload your private key file"
    exit 1
fi

echo "Environment and keys validated"

# Stop any existing services
echo "Stopping existing services..."
docker-compose down --remove-orphans || true

# Build and start services
echo "Building and starting services..."
docker-compose build
docker-compose up -d

# Wait for services to be ready
echo "Waiting for services to be ready..."
sleep 15

# Check service status
echo "Service Status:"
docker-compose ps

# Get external IP for access URLs
EXTERNAL_IP=$(curl -s http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip -H "Metadata-Flavor: Google" || echo "localhost")

echo ""
echo "Services started successfully!"
echo "============================="
echo "OpenWebUI: http://$EXTERNAL_IP:8080"
echo "MCPO API: http://$EXTERNAL_IP:8001/docs"
echo ""
echo "Useful commands:"
echo "   View logs: docker-compose logs -f"
echo "   Restart: docker-compose restart"
echo "   Stop: docker-compose down"
echo ""
echo "Your OpenWebUI + MCPO setup is ready!"

START_EOF

chmod +x "$APP_DIR/scripts/start-services.sh"

# Upload files to VM
echo "Uploading files to VM..."
gcloud compute scp --recurse "$APP_DIR" $INSTANCE_NAME:/home/$(whoami)/ --zone=$ZONE

# Move files to correct location and set permissions
echo "Setting up files on VM..."
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command="
sudo rm -rf /app/* 2>/dev/null || true
sudo cp -r /home/$(whoami)/app/* /app/
sudo chown -R appuser:appuser /app
sudo chmod +x /app/scripts/*.sh
echo 'Files uploaded and permissions set'
"

# Clean up
rm -rf "$TEMP_DIR"

# Get VM external IP
EXTERNAL_IP=$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format='get(networkInterfaces[0].accessConfigs[0].natIP)')

echo ""
echo "Upload Complete!"
echo "==============="
echo "Files uploaded to VM: $INSTANCE_NAME"
echo "VM External IP: $EXTERNAL_IP"
echo ""
echo "Next Steps:"
echo "1. Connect to VM: gcloud compute ssh $INSTANCE_NAME --zone=$ZONE"
echo "2. Set up environment: cd /app && cp .env.template .env && vim .env"
echo "3. Upload Snowflake key: mkdir -p /app/keys && upload comp_role_key.p8"
echo "4. Start services: cd /app && ./scripts/start-services.sh"
echo ""
echo "Quick setup command:"
echo "   ./scripts/deploy-app-to-vm.sh  # Automated setup" 