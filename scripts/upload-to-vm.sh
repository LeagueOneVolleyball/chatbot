#!/bin/bash

set -e

echo "Uploading Application Files to GCP VM"
echo "======================================"

# Configuration
PROJECT_ID="comp-tool-poc-lovb"
ZONE="us-central1-a"
INSTANCE_NAME="openwebui-mcpo"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if VM exists
if ! gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE >/dev/null 2>&1; then
    log_error "VM $INSTANCE_NAME not found in zone $ZONE"
    echo "   Run ./scripts/deploy-gcp-vm.sh first to create the VM"
    exit 1
fi

log_info "Found VM: $INSTANCE_NAME"

# Create temporary directory with all files
log_info "Preparing files for upload..."
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

# Create logs directory structure
mkdir -p "$APP_DIR/logs"
touch "$APP_DIR/logs/.gitkeep"

# Create keys directory structure (empty for now, key will be uploaded separately)
mkdir -p "$APP_DIR/keys"
touch "$APP_DIR/keys/.gitkeep"

# Update docker-compose.yml for VM deployment with proper permissions
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

# Create robust start-services script for the VM
cat > "$APP_DIR/scripts/start-services.sh" << 'START_EOF'
#!/bin/bash

set -e

echo "Starting OpenWebUI + MCPO Services on GCP VM"
echo "============================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if .env file exists
    if [ ! -f .env ]; then
        log_error ".env file not found. Please ensure the deployment script created one."
        exit 1
    fi
    
    # Check if keys directory exists and has proper permissions
    if [ ! -d "keys" ]; then
        log_error "Keys directory not found. Please ensure deployment script uploaded the private key."
        exit 1
    fi
    
    if [ ! -f "keys/comp_role_key.p8" ]; then
        log_error "Snowflake private key not found at keys/comp_role_key.p8"
        exit 1
    fi
    
    # Check and fix file permissions for Docker containers
    log_info "Setting up proper file permissions for Docker containers..."
    
    # Ensure proper ownership and permissions for keys (UID 1001 = appuser in containers)
    sudo chown 1001:1001 keys/comp_role_key.p8
    sudo chmod 644 keys/comp_role_key.p8
    
    # Ensure proper ownership and permissions for .env file
    sudo chown 1001:1001 .env
    sudo chmod 644 .env
    
    # Ensure proper ownership for logs directory
    sudo chown -R 1001:1001 logs/
    sudo chmod -R 755 logs/
    
    log_info "File permissions configured for Docker containers"
}

# Function to validate environment
validate_environment() {
    log_info "Validating environment configuration..."
    
    # Load environment variables
    set -a
    source .env
    set +a
    
    # Check required variables
    local required_vars=(
        "OPENAI_API_KEY"
        "SNOWFLAKE_ACCOUNT" 
        "SNOWFLAKE_USER"
    )
    
    local missing_vars=()
    for var in "${required_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            missing_vars+=("$var")
        fi
    done
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        log_error "Missing required environment variables:"
        for var in "${missing_vars[@]}"; do
            echo "  - $var"
        done
        exit 1
    fi
    
    log_info "Environment validation passed"
}

# Function to start services
start_services() {
    log_info "Starting Docker services..."
    
    # Stop any existing services
    log_info "Stopping existing services..."
    sudo docker-compose down --remove-orphans || true
    
    # Clean up Docker system
    log_info "Cleaning up Docker system..."
    sudo docker system prune -f || true
    
    # Build services
    log_info "Building Docker images..."
    sudo docker-compose build || {
        log_error "Failed to build Docker images"
        exit 1
    }
    
    # Start services
    log_info "Starting services..."
    sudo docker-compose up -d || {
        log_error "Failed to start services"
        log_info "Checking logs for troubleshooting..."
        sudo docker-compose logs || true
        exit 1
    }
    
    log_info "Services started successfully"
}

# Function to wait for services to be healthy
wait_for_services() {
    log_info "Waiting for services to be ready..."
    
    local max_attempts=24  # 6 minutes total (24 * 15 seconds)
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        log_info "Health check attempt $attempt/$max_attempts..."
        
        # Check MCPO service health
        local mcpo_status=$(sudo docker-compose ps mcpo-tools --format json 2>/dev/null | jq -r '.[0].Health // "unknown"' 2>/dev/null || echo "unknown")
        
        # Check OpenWebUI service health  
        local webui_status=$(sudo docker-compose ps openwebui --format json 2>/dev/null | jq -r '.[0].Health // "unknown"' 2>/dev/null || echo "unknown")
        
        log_info "MCPO Status: $mcpo_status, OpenWebUI Status: $webui_status"
        
        if [[ "$mcpo_status" == "healthy" && "$webui_status" == "healthy" ]]; then
            log_info "All services are healthy!"
            return 0
        fi
        
        if [ $attempt -eq $max_attempts ]; then
            log_warn "Services may not be fully ready after maximum wait time"
            log_info "Current service status:"
            sudo docker-compose ps
            log_info "Recent logs:"
            sudo docker-compose logs --tail=20
            return 1
        fi
        
        sleep 15
        ((attempt++))
    done
}

# Function to display final status
display_status() {
    # Get external IP
    local external_ip=$(curl -s http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip -H "Metadata-Flavor: Google" 2>/dev/null || echo "localhost")
    
    echo ""
    echo "🎉 Services Started Successfully!"
    echo "================================"
    echo ""
    echo "🌐 Access URLs:"
    echo "   OpenWebUI: http://$external_ip:8080"
    echo "   MCPO API:  http://$external_ip:8001/docs"
    echo ""
    echo "📊 Service Status:"
    sudo docker-compose ps
    echo ""
    echo "🔧 Useful Commands:"
    echo "   View logs:     sudo docker-compose logs -f"
    echo "   Restart all:   sudo docker-compose restart"
    echo "   Stop all:      sudo docker-compose down"
    echo "   Service logs:  sudo docker-compose logs <service_name>"
    echo ""
    echo "✅ Your OpenWebUI + MCPO setup is ready!"
}

# Main execution flow
main() {
    log_info "Starting service startup process..."
    
    # Step 1: Check prerequisites and fix permissions
    check_prerequisites
    
    # Step 2: Validate environment
    validate_environment
    
    # Step 3: Start services
    start_services
    
    # Step 4: Wait for services to be healthy
    if wait_for_services; then
        log_info "All services are healthy and ready"
    else
        log_warn "Services started but may not be fully ready"
    fi
    
    # Step 5: Display final status
    display_status
}

# Error handling
trap 'log_error "Service startup failed at line $LINENO. Check the error above."' ERR

# Run main
main "$@"
START_EOF

chmod +x "$APP_DIR/scripts/start-services.sh"

# Upload files to VM
log_info "Uploading files to VM..."
gcloud compute scp --recurse "$APP_DIR" $INSTANCE_NAME:/home/$(whoami)/ --zone=$ZONE || {
    log_error "Failed to upload files to VM"
    rm -rf "$TEMP_DIR"
    exit 1
}

# Move files to correct location and set initial permissions
log_info "Setting up files on VM..."
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command="
    # Remove old app directory contents
    sudo rm -rf /app/* 2>/dev/null || true
    
    # Copy new files
    sudo cp -r /home/$(whoami)/app/* /app/
    
    # Set ownership to appuser (UID 1001) for Docker compatibility
    sudo chown -R 1001:1001 /app
    
    # Set execute permissions on scripts
    sudo chmod +x /app/scripts/*.sh
    
    # Set proper permissions for directories
    sudo chmod 755 /app/logs /app/keys
    
    echo 'Files uploaded and initial permissions set'
" || {
    log_error "Failed to set up files on VM"
    rm -rf "$TEMP_DIR"
    exit 1
}

# Clean up
rm -rf "$TEMP_DIR"

# Get VM external IP
EXTERNAL_IP=$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format='get(networkInterfaces[0].accessConfigs[0].natIP)')

echo ""
log_info "Upload Complete!"
echo "==============="
echo "Files uploaded to VM: $INSTANCE_NAME"
echo "VM External IP: $EXTERNAL_IP"
echo ""
echo "🔧 Next Steps:"
echo "1. The main deployment script will:"
echo "   - Upload environment configuration"
echo "   - Upload and secure Snowflake private key"
echo "   - Start services automatically"
echo ""
echo "📁 File Structure on VM:"
echo "   /app/                    - Application root"
echo "   /app/.env               - Environment configuration (to be created)"
echo "   /app/keys/              - Private keys directory"
echo "   /app/logs/              - Application logs"
echo "   /app/scripts/           - Management scripts"
echo ""
echo "🚀 Ready for deployment completion!" 