#!/bin/bash
#
# deploy-gcp-vm.sh
# Deploy a GCP VM instance for OpenWebUI + MCPO setup
#
# Usage: ./scripts/deploy-gcp-vm.sh
#
# Requirements:
#   - gcloud CLI installed and authenticated
#   - Proper permissions for GCP project
#
# Environment Variables:
#   PROJECT_ID: GCP project ID (default: comp-tool-poc-lovb)
#   REGION: GCP region (default: us-central1)
#   ZONE: GCP zone (default: us-central1-a)

set -euo pipefail

# Enable debug mode if DEBUG is set
if [[ "${DEBUG:-}" == "true" ]]; then
    set -x
fi

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly LOG_PREFIX="[$SCRIPT_NAME]"

# Function for consistent logging
log() {
    echo "$LOG_PREFIX $*" >&2
}

log_error() {
    echo "$LOG_PREFIX ERROR: $*" >&2
}

log_warning() {
    echo "$LOG_PREFIX WARNING: $*" >&2
}

log "Deploying OpenWebUI + MCPO to GCP VM"
log "===================================="
log "Project: comp-tool-poc-lovb"
log "Organization: thedataloft.com"
log ""

# Configuration with environment variable overrides
readonly PROJECT_ID="${PROJECT_ID:-comp-tool-poc-lovb}"
readonly REGION="${REGION:-us-central1}"
readonly ZONE="${ZONE:-us-central1-a}"
readonly INSTANCE_NAME="${INSTANCE_NAME:-openwebui-mcpo}"
readonly MACHINE_TYPE="${MACHINE_TYPE:-e2-standard-2}"  # 2 vCPUs, 8GB RAM
readonly DISK_SIZE="${DISK_SIZE:-50GB}"
readonly IMAGE_FAMILY="ubuntu-2204-lts"
readonly IMAGE_PROJECT="ubuntu-os-cloud"

# Network configuration
readonly NETWORK_NAME="openwebui-network"
readonly FIREWALL_NAME="openwebui-firewall"

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI not found. Please install Google Cloud SDK"
        exit 1
    fi
    
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        log_error "Not authenticated. Please run: gcloud auth login"
        exit 1
    fi
    
    log "Prerequisites check passed"
}

# Function to setup GCP project
setup_project() {
    log "Setting project to $PROJECT_ID..."
    if ! gcloud config set project "$PROJECT_ID"; then
        log_error "Failed to set project. Please check permissions"
        exit 1
    fi
    
    log "Enabling required APIs..."
    gcloud services enable compute.googleapis.com secretmanager.googleapis.com logging.googleapis.com
}

# Function to setup networking
setup_network() {
    log "Setting up network..."
    
    if ! gcloud compute networks describe "$NETWORK_NAME" >/dev/null 2>&1; then
        log "Creating VPC network: $NETWORK_NAME"
        gcloud compute networks create "$NETWORK_NAME" \
            --subnet-mode=auto \
            --description="Network for OpenWebUI + MCPO deployment"
    else
        log "Network $NETWORK_NAME already exists"
    fi
    
    if ! gcloud compute firewall-rules describe "$FIREWALL_NAME" >/dev/null 2>&1; then
        log "Creating firewall rule: $FIREWALL_NAME"
        gcloud compute firewall-rules create "$FIREWALL_NAME" \
            --network="$NETWORK_NAME" \
            --action=allow \
            --rules=tcp:8080,tcp:8001,tcp:22 \
            --source-ranges=0.0.0.0/0 \
            --description="Allow OpenWebUI (8080), MCPO (8001), and SSH (22)" \
            --target-tags=openwebui-server
    else
        log "Firewall rule $FIREWALL_NAME already exists"
    fi
}

# Function to create startup script
create_startup_script() {
    log "Creating VM startup script..."
    
    cat > /tmp/startup-script.sh << 'STARTUP_EOF'
#!/bin/bash

set -euo pipefail

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [STARTUP] $*" | tee -a /var/log/startup-script.log
}

log "Starting VM initialization..."

# Update system
log "Updating system packages..."
apt-get update
apt-get upgrade -y

# Install Docker
log "Installing Docker..."
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
systemctl enable docker
systemctl start docker

# Install Docker Compose
log "Installing Docker Compose..."
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Create app user
log "Creating application user..."
useradd -m -G docker appuser

# Create application directory
log "Setting up application directory..."
mkdir -p /app
cd /app
mkdir -p {config,logs,scripts}

# Create basic docker-compose.yml placeholder
cat > docker-compose.yml << 'COMPOSE_EOF'
# This will be replaced with your actual docker-compose.yml
version: '3.8'
services:
  placeholder:
    image: hello-world
COMPOSE_EOF

# Set permissions
chown -R appuser:appuser /app

# Create systemd service for auto-start
log "Creating systemd service..."
cat > /etc/systemd/system/openwebui.service << 'SERVICE_EOF'
[Unit]
Description=OpenWebUI + MCPO Services
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/app
ExecStart=/usr/local/bin/docker-compose up -d
ExecStop=/usr/local/bin/docker-compose down
User=appuser
Group=docker

[Install]
WantedBy=multi-user.target
SERVICE_EOF

# Enable the service (but don't start yet - need actual files)
systemctl enable openwebui.service

# Install useful tools
log "Installing additional tools..."
apt-get install -y htop curl wget git vim

log "VM setup completed successfully"

STARTUP_EOF
}

# Function to create VM instance
create_vm_instance() {
    log "Creating VM instance: $INSTANCE_NAME..."
    
    if gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" >/dev/null 2>&1; then
        log_warning "VM $INSTANCE_NAME already exists. Delete it first or use a different name."
        log "   To delete: gcloud compute instances delete $INSTANCE_NAME --zone=$ZONE"
        read -p "   Delete existing VM and recreate? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log "Deleting existing VM..."
            gcloud compute instances delete "$INSTANCE_NAME" --zone="$ZONE" --quiet
        else
            log "Deployment cancelled"
            exit 1
        fi
    fi
    
    log "Creating new VM instance..."
    gcloud compute instances create "$INSTANCE_NAME" \
        --zone="$ZONE" \
        --machine-type="$MACHINE_TYPE" \
        --network-interface=network-tier=PREMIUM,subnet="$NETWORK_NAME" \
        --maintenance-policy=MIGRATE \
        --provisioning-model=STANDARD \
        --tags=openwebui-server \
        --create-disk=auto-delete=yes,boot=yes,device-name="$INSTANCE_NAME",image=projects/"$IMAGE_PROJECT"/global/images/family/"$IMAGE_FAMILY",mode=rw,size="$DISK_SIZE",type=projects/"$PROJECT_ID"/zones/"$ZONE"/diskTypes/pd-standard \
        --metadata-from-file startup-script=/tmp/startup-script.sh \
        --scopes=https://www.googleapis.com/auth/cloud-platform
}

# Function to show deployment results
show_results() {
    # Clean up temp file
    rm -f /tmp/startup-script.sh
    
    # Wait for VM to be ready
    log "Waiting for VM to be ready..."
    sleep 30
    
    # Get VM external IP
    local external_ip
    external_ip=$(gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
    
    log ""
    log "VM Deployment Complete!"
    log "======================="
    log "Instance Details:"
    log "   Name: $INSTANCE_NAME"
    log "   Zone: $ZONE"
    log "   External IP: $external_ip"
    log "   Machine Type: $MACHINE_TYPE"
    log ""
    log "Access Information:"
    log "   SSH: gcloud compute ssh $INSTANCE_NAME --zone=$ZONE"
    log "   OpenWebUI (when deployed): http://$external_ip:8080"
    log "   MCPO API (when deployed): http://$external_ip:8001/docs"
    log ""
    log "Next Steps:"
    log "1. Upload your application files to the VM"
    log "2. Configure environment variables and secrets"
    log "3. Start the services"
    log ""
    log "Quick commands:"
    log "   Connect to VM: gcloud compute ssh $INSTANCE_NAME --zone=$ZONE"
    log "   Upload files: ./scripts/upload-to-vm.sh"
    log "   Deploy app: ./scripts/deploy-app-to-vm.sh"
    log ""
    log "Security Note: The VM is accessible from the internet."
    log "   Make sure to configure proper authentication and secrets!"
}

# Main execution flow
main() {
    check_prerequisites
    setup_project
    setup_network
    create_startup_script
    create_vm_instance
    show_results
}

# Execute main function
main "$@" 