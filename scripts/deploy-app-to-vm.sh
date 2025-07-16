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

# Function to prompt for environment variables
setup_environment() {
    echo "Setting up environment configuration..."
    
    # Check if we have a local .env file to use as template
    if [ -f .env ]; then
        echo "Found local .env file. Using as template..."
        ENV_SOURCE=".env"
    elif [ -f env.example ]; then
        echo "Using env.example as template..."
        ENV_SOURCE="env.example"
    else
        echo "ERROR: No environment template found"
        exit 1
    fi
    
    # Read required values
    echo ""
    echo "Please provide the following configuration:"
    echo "(Press Enter to use default values shown in brackets)"
    echo ""
    
    # OpenAI API Key
    read -p "OpenAI API Key: " OPENAI_API_KEY
    if [ -z "$OPENAI_API_KEY" ]; then
        echo "ERROR: OpenAI API Key is required"
        exit 1
    fi
    
    # Snowflake Private Key Passphrase
    read -s -p "Snowflake Private Key Passphrase (hidden): " SNOWFLAKE_PRIVATE_KEY_PASSPHRASE
    echo ""
    
    # WebUI Secret Key
    read -p "WebUI Secret Key [auto-generated]: " WEBUI_SECRET_KEY
    if [ -z "$WEBUI_SECRET_KEY" ]; then
        WEBUI_SECRET_KEY=$(openssl rand -hex 32)
        echo "Generated WebUI Secret Key: $WEBUI_SECRET_KEY"
    fi
    
    echo "Environment configuration collected"
}

# Function to upload Snowflake private key
upload_private_key() {
    echo "Setting up Snowflake private key..."
    
    local KEY_PATH="/Users/kevin/dev/keys/comp_role_key.p8"
    
    if [ ! -f "$KEY_PATH" ]; then
        echo "ERROR: Snowflake private key not found at: $KEY_PATH"
        echo "   Please ensure your private key is at this location"
        read -p "   Enter path to your private key file: " KEY_PATH
        
        if [ ! -f "$KEY_PATH" ]; then
            echo "ERROR: Private key file not found: $KEY_PATH"
            exit 1
        fi
    fi
    
    echo "Uploading private key to VM..."
    gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command="sudo mkdir -p /app/keys"
    gcloud compute scp "$KEY_PATH" $INSTANCE_NAME:/home/$(whoami)/comp_role_key.p8 --zone=$ZONE
    gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command="
        sudo mv /home/$(whoami)/comp_role_key.p8 /app/keys/
        sudo chown appuser:appuser /app/keys/comp_role_key.p8
        sudo chmod 600 /app/keys/comp_role_key.p8
    "
    
    echo "Private key uploaded and secured"
}

# Function to create environment file on VM
create_vm_env() {
    echo "Creating environment file on VM..."
    
    # Get VM external IP
    EXTERNAL_IP=$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
    
    # Create environment file content
    ENV_CONTENT="# OpenWebUI + MCP Servers Environment Configuration for GCP VM
# Generated on $(date)

# ============================================================================
# OpenAI Configuration
# ============================================================================
OPENAI_API_KEY=$OPENAI_API_KEY
OPENAI_API_BASE_URL=https://api.openai.com/v1

# ============================================================================
# WebUI Configuration
# ============================================================================
WEBUI_AUTH=false
WEBUI_SECRET_KEY=$WEBUI_SECRET_KEY
WEBUI_URL=http://$EXTERNAL_IP:8080

# ============================================================================
# Snowflake Configuration
# ============================================================================
SNOWFLAKE_ACCOUNT=UPNOBVJ-OK59235
SNOWFLAKE_USER=COMP_SERVICE_ACCOUNT
SNOWFLAKE_PRIVATE_KEY_PATH=/app/keys/comp_role_key.p8
SNOWFLAKE_PRIVATE_KEY_PASSPHRASE=$SNOWFLAKE_PRIVATE_KEY_PASSPHRASE
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
USER_PERMISSIONS_WORKSPACE_TOOLS_ACCESS=true"

    # Upload environment file
    echo "$ENV_CONTENT" | gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command="
        cat > /home/$(whoami)/.env
        sudo mv /home/$(whoami)/.env /app/.env
        sudo chown appuser:appuser /app/.env
        sudo chmod 600 /app/.env
    "
    
    echo "Environment file created on VM"
}

# Main deployment flow
main() {
    # Check if VM exists
    echo "Checking VM status..."
    if ! gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE >/dev/null 2>&1; then
        echo "VM $INSTANCE_NAME not found. Creating VM first..."
        ./scripts/deploy-gcp-vm.sh
    else
        echo "Found existing VM: $INSTANCE_NAME"
    fi
    
    # Upload application files
    echo ""
    echo "Uploading application files..."
    ./scripts/upload-to-vm.sh
    
    # Setup environment
    echo ""
    setup_environment
    
    # Upload private key
    echo ""
    upload_private_key
    
    # Create environment file
    echo ""
    create_vm_env
    
    # Start services
    echo ""
    echo "Starting services on VM..."
    gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command="
        cd /app
        ./scripts/start-services.sh
    "
    
    # Get final status
    EXTERNAL_IP=$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
    
    echo ""
    echo "DEPLOYMENT COMPLETE!"
    echo "==================="
    echo "VM Information:"
    echo "   Instance: $INSTANCE_NAME"
    echo "   Project: $PROJECT_ID"
    echo "   Zone: $ZONE"
    echo "   External IP: $EXTERNAL_IP"
    echo ""
    echo "Access URLs:"
    echo "   OpenWebUI: http://$EXTERNAL_IP:8080"
    echo "   MCPO API: http://$EXTERNAL_IP:8001/docs"
    echo ""
    echo "Management Commands:"
    echo "   Connect to VM: gcloud compute ssh $INSTANCE_NAME --zone=$ZONE"
    echo "   View logs: gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command='cd /app && docker-compose logs -f'"
    echo "   Restart services: gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command='cd /app && docker-compose restart'"
    echo "   Stop services: gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command='cd /app && docker-compose down'"
    echo ""
    echo "Security Notes:"
    echo "   - VM is accessible from the internet on ports 8080 and 8001"
    echo "   - Consider enabling WebUI authentication for production use"
    echo "   - Private keys are stored securely with proper permissions"
    echo ""
    echo "Your OpenWebUI + MCPO setup is ready for use!"
    echo ""
    echo "Next: Visit http://$EXTERNAL_IP:8080 to start using OpenWebUI!"
}

# Check for required tools
if ! command -v gcloud &> /dev/null; then
    echo "ERROR: gcloud CLI not found. Please install Google Cloud SDK"
    exit 1
fi

if ! command -v openssl &> /dev/null; then
    echo "ERROR: openssl not found. Please install openssl"
    exit 1
fi

# Run main deployment
main 