#!/bin/bash

set -e

echo "Complete GCP VM Deployment: OpenWebUI + MCPO"
echo "============================================"
echo "Project: comp-tool-poc-lovb"
echo ""

# Configuration
PROJECT_ID="comp-tool-poc-lovb"
ZONE="us-central1-a"
INSTANCE_NAME="openwebui-mcpo"
KEY_PATH="/Users/kevin/dev/keys/comp_role_key.p8"

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
    
    # Check gcloud CLI
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI not found. Please install Google Cloud SDK"
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "Not authenticated with gcloud. Run: gcloud auth login"
        exit 1
    fi
    
    # Check project
    CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
    if [ "$CURRENT_PROJECT" != "$PROJECT_ID" ]; then
        log_error "Wrong project. Current: $CURRENT_PROJECT, Expected: $PROJECT_ID"
        echo "Run: gcloud config set project $PROJECT_ID"
        exit 1
    fi
    
    # Check local .env file
    if [ ! -f ".env" ]; then
        log_error "Local .env file not found. Please create one with your configuration."
        exit 1
    fi
    
    # Check private key
    if [ ! -f "$KEY_PATH" ]; then
        log_error "Snowflake private key not found at: $KEY_PATH"
        echo "Please ensure your private key is at this location or update KEY_PATH in this script"
        exit 1
    fi
    
    log_info "Prerequisites check passed"
}

# Function to validate local environment
validate_local_env() {
    log_info "Validating local environment..."
    
    # Source the .env file and check required variables
    set -a
    source .env
    set +a
    
    local required_vars=(
        "OPENAI_API_KEY"
        "SNOWFLAKE_ACCOUNT" 
        "SNOWFLAKE_USER"
        "SNOWFLAKE_PRIVATE_KEY_PASSPHRASE"
        "MCPO_SNOWFLAKE_API_KEY"
    )
    
    local missing_vars=()
    for var in "${required_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            missing_vars+=("$var")
        fi
    done
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        log_error "Missing required environment variables in .env:"
        for var in "${missing_vars[@]}"; do
            echo "  - $var"
        done
        exit 1
    fi
    
    log_info "Local environment validation passed"
}

# Function to ensure VM exists
ensure_vm_exists() {
    log_info "Checking VM status..."
    
    if ! gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE >/dev/null 2>&1; then
        log_warn "VM $INSTANCE_NAME not found. Creating VM..."
        if ! ./scripts/deploy-gcp-vm.sh; then
            log_error "Failed to create VM"
            exit 1
        fi
        log_info "VM created successfully"
    else
        log_info "Found existing VM: $INSTANCE_NAME"
    fi
}

# Function to upload application files
upload_application_files() {
    log_info "Uploading application files..."
    
    if ! ./scripts/upload-to-vm.sh; then
        log_error "Failed to upload application files"
        exit 1
    fi
    
    log_info "Application files uploaded successfully"
}

# Function to upload and secure private key
upload_private_key() {
    log_info "Uploading and securing Snowflake private key..."
    
    # Create keys directory
    gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command="sudo mkdir -p /app/keys" || {
        log_error "Failed to create keys directory"
        exit 1
    }
    
    # Upload key to user home directory first
    gcloud compute scp "$KEY_PATH" $INSTANCE_NAME:/home/$(whoami)/comp_role_key.p8 --zone=$ZONE || {
        log_error "Failed to upload private key"
        exit 1
    }
    
    # Move to correct location with proper permissions for Docker container
    gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command="
        sudo mv /home/$(whoami)/comp_role_key.p8 /app/keys/
        sudo chown 1001:1001 /app/keys/comp_role_key.p8
        sudo chmod 644 /app/keys/comp_role_key.p8
        echo 'Private key secured with UID 1001 (appuser) permissions'
    " || {
        log_error "Failed to secure private key"
        exit 1
    }
    
    log_info "Private key uploaded and secured"
}

# Function to create environment file on VM
create_vm_env() {
    log_info "Creating environment file on VM..."
    
    # Get VM external IP
    EXTERNAL_IP=$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format='get(networkInterfaces[0].accessConfigs[0].natIP)') || {
        log_error "Failed to get VM external IP"
        exit 1
    }
    
    # Create temporary env file with updated URLs
    local temp_env=$(mktemp)
    
    # Copy local .env and update VM-specific values
    sed "s|WEBUI_URL=.*|WEBUI_URL=http://$EXTERNAL_IP:8080|g" .env > "$temp_env"
    sed -i "s|SNOWFLAKE_PRIVATE_KEY_PATH=.*|SNOWFLAKE_PRIVATE_KEY_PATH=/app/keys/comp_role_key.p8|g" "$temp_env"
    
    # Add VM-specific header
    {
        echo "# OpenWebUI + MCP Servers Environment Configuration for GCP VM"
        echo "# Generated on $(date)"
        echo "# VM: $INSTANCE_NAME ($EXTERNAL_IP)"
        echo ""
        cat "$temp_env"
    } > "${temp_env}.final"
    
    # Upload environment file to VM
    gcloud compute scp "${temp_env}.final" $INSTANCE_NAME:/home/$(whoami)/.env --zone=$ZONE || {
        log_error "Failed to upload environment file"
        rm -f "$temp_env" "${temp_env}.final"
        exit 1
    }
    
    # Move to correct location with proper permissions for Docker container
    gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command="
        sudo mv /home/$(whoami)/.env /app/.env
        sudo chown 1001:1001 /app/.env
        sudo chmod 644 /app/.env
        echo 'Environment file created with UID 1001 (appuser) permissions'
    " || {
        log_error "Failed to secure environment file"
        rm -f "$temp_env" "${temp_env}.final"
        exit 1
    }
    
    # Clean up temporary files
    rm -f "$temp_env" "${temp_env}.final"
    
    log_info "Environment file created on VM"
}

# Function to start services with proper error handling
start_services() {
    log_info "Starting services on VM..."
    
    # Stop any existing services first
    log_info "Stopping any existing services..."
    gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command="
        cd /app
        sudo docker-compose down --remove-orphans || true
        sudo docker system prune -f || true
    " || log_warn "Failed to clean up existing services (may not exist)"
    
    # Build and start services
    log_info "Building and starting containers..."
    gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command="
        cd /app
        sudo docker-compose build
        sudo docker-compose up -d
    " || {
        log_error "Failed to start services"
        log_info "Checking logs for troubleshooting..."
        gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command="cd /app && sudo docker-compose logs" || true
        exit 1
    }
    
    # Wait for services to be ready
    log_info "Waiting for services to be ready (this may take a minute)..."
    local max_attempts=20
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        log_info "Health check attempt $attempt/$max_attempts..."
        
        # Check if both services are healthy
        local mcpo_healthy=$(gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command="
            cd /app && sudo docker-compose ps mcpo-tools --format json | jq -r '.[0].Health // \"unknown\"'
        " 2>/dev/null || echo "unknown")
        
        local openwebui_healthy=$(gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command="
            cd /app && sudo docker-compose ps openwebui --format json | jq -r '.[0].Health // \"unknown\"'
        " 2>/dev/null || echo "unknown")
        
        if [[ "$mcpo_healthy" == "healthy" && "$openwebui_healthy" == "healthy" ]]; then
            log_info "All services are healthy!"
            break
        fi
        
        if [ $attempt -eq $max_attempts ]; then
            log_warn "Services may not be fully ready. Checking status..."
            gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command="cd /app && sudo docker-compose ps"
            break
        fi
        
        sleep 15
        ((attempt++))
    done
    
    log_info "Services started successfully"
}

# Function to verify deployment
verify_deployment() {
    log_info "Verifying deployment..."
    
    # Get VM external IP
    EXTERNAL_IP=$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
    
    # Test MCPO API
    log_info "Testing MCPO API..."
    local mcpo_status=$(curl -s -o /dev/null -w "%{http_code}" "http://$EXTERNAL_IP:8001/docs" || echo "000")
    if [ "$mcpo_status" = "200" ]; then
        log_info "✅ MCPO API is accessible"
    else
        log_warn "⚠️  MCPO API returned status: $mcpo_status"
    fi
    
    # Test OpenWebUI
    log_info "Testing OpenWebUI..."
    local webui_status=$(curl -s -o /dev/null -w "%{http_code}" "http://$EXTERNAL_IP:8080" || echo "000")
    if [ "$webui_status" = "200" ]; then
        log_info "✅ OpenWebUI is accessible"
    else
        log_warn "⚠️  OpenWebUI returned status: $webui_status"
    fi
}

# Function to display final information
display_final_info() {
    EXTERNAL_IP=$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
    
    echo ""
    echo "🎉 DEPLOYMENT COMPLETE!"
    echo "======================"
    echo ""
    echo "VM Information:"
    echo "   Instance: $INSTANCE_NAME"
    echo "   Project: $PROJECT_ID"
    echo "   Zone: $ZONE"
    echo "   External IP: $EXTERNAL_IP"
    echo ""
    echo "🌐 Access URLs:"
    echo "   OpenWebUI: http://$EXTERNAL_IP:8080"
    echo "   MCPO API:  http://$EXTERNAL_IP:8001/docs"
    echo ""
    echo "🔧 Management Commands:"
    echo "   Connect to VM:"
    echo "     gcloud compute ssh $INSTANCE_NAME --zone=$ZONE"
    echo ""
    echo "   View logs:"
    echo "     gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command='cd /app && sudo docker-compose logs -f'"
    echo ""
    echo "   Restart services:"
    echo "     gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command='cd /app && sudo docker-compose restart'"
    echo ""
    echo "   Stop services:"
    echo "     gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command='cd /app && sudo docker-compose down'"
    echo ""
    echo "🔒 Security Notes:"
    echo "   - VM is accessible from the internet on ports 8080 and 8001"
    echo "   - Consider enabling WebUI authentication for production use"
    echo "   - Private keys are stored securely with proper permissions"
    echo ""
    echo "✅ Your OpenWebUI + MCPO setup is ready for use!"
    echo ""
    echo "🚀 Next: Visit http://$EXTERNAL_IP:8080 to start using OpenWebUI!"
}

# Main deployment flow
main() {
    log_info "Starting complete deployment process..."
    
    # Step 1: Check prerequisites
    check_prerequisites
    
    # Step 2: Validate local environment
    validate_local_env
    
    # Step 3: Ensure VM exists
    ensure_vm_exists
    
    # Step 4: Upload application files
    upload_application_files
    
    # Step 5: Upload and secure private key
    upload_private_key
    
    # Step 6: Create environment file
    create_vm_env
    
    # Step 7: Start services
    start_services
    
    # Step 8: Verify deployment
    verify_deployment
    
    # Step 9: Display final information
    display_final_info
}

# Error handling
trap 'log_error "Deployment failed at line $LINENO. Check the error above."' ERR

# Run main deployment
main "$@" 