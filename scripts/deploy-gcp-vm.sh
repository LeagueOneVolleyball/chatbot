#!/bin/bash

set -e

echo "Deploying OpenWebUI + MCPO to GCP VM"
echo "===================================="
echo "Project: comp-tool-poc-lovb"
echo "Organization: thedataloft.com"
echo ""

# Configuration
PROJECT_ID="comp-tool-poc-lovb"
REGION="us-central1"
ZONE="us-central1-a"
INSTANCE_NAME="openwebui-mcpo"
MACHINE_TYPE="e2-standard-2"  # 2 vCPUs, 8GB RAM
DISK_SIZE="50GB"
IMAGE_FAMILY="ubuntu-2204-lts"
IMAGE_PROJECT="ubuntu-os-cloud"

# Network configuration
NETWORK_NAME="openwebui-network"
FIREWALL_NAME="openwebui-firewall"

# Check if authenticated
echo "Checking authentication..."
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
    echo "ERROR: Not authenticated. Please run: gcloud auth login"
    exit 1
fi

# Set project
echo "Setting project to $PROJECT_ID..."
gcloud config set project $PROJECT_ID

# Enable required APIs
echo "Enabling required APIs..."
gcloud services enable compute.googleapis.com
gcloud services enable secretmanager.googleapis.com
gcloud services enable logging.googleapis.com

# Create network if it doesn't exist
echo "Setting up network..."
if ! gcloud compute networks describe $NETWORK_NAME >/dev/null 2>&1; then
    echo "Creating VPC network: $NETWORK_NAME"
    gcloud compute networks create $NETWORK_NAME \
        --subnet-mode=auto \
        --description="Network for OpenWebUI + MCPO deployment"
else
    echo "Network $NETWORK_NAME already exists"
fi

# Create firewall rules
echo "Setting up firewall rules..."
if ! gcloud compute firewall-rules describe $FIREWALL_NAME >/dev/null 2>&1; then
    echo "Creating firewall rule: $FIREWALL_NAME"
    gcloud compute firewall-rules create $FIREWALL_NAME \
        --network=$NETWORK_NAME \
        --action=allow \
        --rules=tcp:8080,tcp:8001,tcp:22 \
        --source-ranges=0.0.0.0/0 \
        --description="Allow OpenWebUI (8080), MCPO (8001), and SSH (22)" \
        --target-tags=openwebui-server
else
    echo "Firewall rule $FIREWALL_NAME already exists"
fi

# Create startup script
echo "Creating VM startup script..."
cat > /tmp/startup-script.sh << 'STARTUP_EOF'
#!/bin/bash

# Update system
apt-get update
apt-get upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
systemctl enable docker
systemctl start docker

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Create app user
useradd -m -G docker appuser

# Create application directory
mkdir -p /app
cd /app

# Clone or copy application files (you'll need to upload these)
# For now, create the directory structure
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
apt-get install -y htop curl wget git vim

# Log completion
echo "$(date): VM setup completed" >> /var/log/startup-script.log

STARTUP_EOF

# Create the VM instance
echo "Creating VM instance: $INSTANCE_NAME..."
if gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE >/dev/null 2>&1; then
    echo "WARNING: VM $INSTANCE_NAME already exists. Delete it first or use a different name."
    echo "   To delete: gcloud compute instances delete $INSTANCE_NAME --zone=$ZONE"
    read -p "   Delete existing VM and recreate? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Deleting existing VM..."
        gcloud compute instances delete $INSTANCE_NAME --zone=$ZONE --quiet
    else
        echo "Deployment cancelled"
        exit 1
    fi
fi

echo "Creating new VM instance..."
gcloud compute instances create $INSTANCE_NAME \
    --zone=$ZONE \
    --machine-type=$MACHINE_TYPE \
    --network-interface=network-tier=PREMIUM,subnet=$NETWORK_NAME \
    --maintenance-policy=MIGRATE \
    --provisioning-model=STANDARD \
    --tags=openwebui-server \
    --create-disk=auto-delete=yes,boot=yes,device-name=$INSTANCE_NAME,image=projects/$IMAGE_PROJECT/global/images/family/$IMAGE_FAMILY,mode=rw,size=$DISK_SIZE,type=projects/$PROJECT_ID/zones/$ZONE/diskTypes/pd-standard \
    --metadata-from-file startup-script=/tmp/startup-script.sh \
    --scopes=https://www.googleapis.com/auth/cloud-platform

# Clean up temp file
rm -f /tmp/startup-script.sh

# Wait for VM to be ready
echo "Waiting for VM to be ready..."
sleep 30

# Get VM external IP
EXTERNAL_IP=$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format='get(networkInterfaces[0].accessConfigs[0].natIP)')

echo ""
echo "VM Deployment Complete!"
echo "======================="
echo "Instance Details:"
echo "   Name: $INSTANCE_NAME"
echo "   Zone: $ZONE"
echo "   External IP: $EXTERNAL_IP"
echo "   Machine Type: $MACHINE_TYPE"
echo ""
echo "Access Information:"
echo "   SSH: gcloud compute ssh $INSTANCE_NAME --zone=$ZONE"
echo "   OpenWebUI (when deployed): http://$EXTERNAL_IP:8080"
echo "   MCPO API (when deployed): http://$EXTERNAL_IP:8001/docs"
echo ""
echo "Next Steps:"
echo "1. Upload your application files to the VM"
echo "2. Configure environment variables and secrets"
echo "3. Start the services"
echo ""
echo "Quick commands:"
echo "   Connect to VM: gcloud compute ssh $INSTANCE_NAME --zone=$ZONE"
echo "   Upload files: ./scripts/upload-to-vm.sh"
echo "   Deploy app: ./scripts/deploy-app-to-vm.sh"
echo ""
echo "Security Note: The VM is accessible from the internet."
echo "   Make sure to configure proper authentication and secrets!" 