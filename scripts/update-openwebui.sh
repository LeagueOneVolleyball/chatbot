#!/bin/bash

set -e

echo "Updating Open WebUI Container on GCP VM"
echo "======================================="

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
    
    # Check if VM exists
    if ! gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE >/dev/null 2>&1; then
        log_error "VM $INSTANCE_NAME not found in zone $ZONE"
        exit 1
    fi
    
    log_info "Prerequisites check passed"
}

# Function to get current Open WebUI version
get_current_version() {
    log_info "Checking current Open WebUI version on VM..."
    
    local current_version=$(gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command="
        cd /app
        sudo docker images ghcr.io/open-webui/open-webui --format 'table {{.Tag}}\t{{.CreatedAt}}' | grep -v TAG | head -1
    " 2>/dev/null || echo "unknown")
    
    if [ "$current_version" != "unknown" ]; then
        log_info "Current version info: $current_version"
    else
        log_warn "Could not determine current version"
    fi
}

# Function to backup current data
backup_data() {
    log_info "Creating backup of OpenWebUI data..."
    
    gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command="
        cd /app
        
        # Create backup directory with timestamp
        BACKUP_DIR=\"/app/backups/$(date +%Y%m%d_%H%M%S)\"
        sudo mkdir -p \"\$BACKUP_DIR\"
        
        # Backup docker volume data
        if sudo docker volume inspect openwebui_data >/dev/null 2>&1; then
            log_info 'Backing up OpenWebUI data volume...'
            sudo docker run --rm -v openwebui_data:/data -v \"\$BACKUP_DIR\":/backup alpine tar czf /backup/openwebui_data_backup.tar.gz -C /data .
            echo \"Data backup created at \$BACKUP_DIR/openwebui_data_backup.tar.gz\"
        else
            echo 'No OpenWebUI data volume found to backup'
        fi
        
        # Backup current logs
        if [ -d '/app/logs' ]; then
            sudo cp -r /app/logs \"\$BACKUP_DIR/logs_backup\"
            echo \"Logs backup created at \$BACKUP_DIR/logs_backup\"
        fi
        
        echo \"Backup completed at \$BACKUP_DIR\"
    " || {
        log_error "Failed to create backup"
        exit 1
    }
    
    log_info "Backup completed successfully"
}

# Function to update Open WebUI container
update_openwebui() {
    log_info "Updating Open WebUI container..."
    
    gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command="
        cd /app
        
        echo 'Stopping current services...'
        sudo docker-compose down
        
        echo 'Pulling latest Open WebUI image...'
        sudo docker pull ghcr.io/open-webui/open-webui:main
        
        echo 'Cleaning up old images...'
        sudo docker image prune -f
        
        echo 'Rebuilding containers with latest image...'
        sudo docker-compose build --no-cache openwebui
        
        echo 'Starting updated services...'
        sudo docker-compose up -d
        
        echo 'Update completed successfully'
    " || {
        log_error "Failed to update Open WebUI container"
        exit 1
    }
    
    log_info "Open WebUI container updated successfully"
}

# Function to wait for services to be healthy
wait_for_services() {
    log_info "Waiting for services to be ready after update..."
    
    local max_attempts=20
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        log_info "Health check attempt $attempt/$max_attempts..."
        
        # Check if both services are healthy using correct JSON parsing
        local mcpo_healthy=$(gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command="
            cd /app && sudo docker-compose ps mcpo-tools --format json | jq -r '.Health // \"unknown\"'
        " 2>/dev/null || echo "unknown")
        
        local openwebui_healthy=$(gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command="
            cd /app && sudo docker-compose ps openwebui --format json | jq -r '.Health // \"unknown\"'
        " 2>/dev/null || echo "unknown")
        
        log_info "MCPO Status: $mcpo_healthy, OpenWebUI Status: $openwebui_healthy"
        
        if [[ "$mcpo_healthy" == "healthy" && "$openwebui_healthy" == "healthy" ]]; then
            log_info "All services are healthy after update!"
            return 0
        fi
        
        if [ $attempt -eq $max_attempts ]; then
            log_warn "Services may not be fully ready. Checking status..."
            gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command="cd /app && sudo docker-compose ps"
            gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command="cd /app && sudo docker-compose logs --tail=10 openwebui"
            return 1
        fi
        
        sleep 15
        ((attempt++))
    done
}

# Function to verify the update
verify_update() {
    log_info "Verifying update..."
    
    # Get VM external IP
    EXTERNAL_IP=$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
    
    # Test OpenWebUI accessibility
    log_info "Testing OpenWebUI accessibility..."
    local webui_status=$(curl -s -o /dev/null -w "%{http_code}" "http://$EXTERNAL_IP:8080" || echo "000")
    if [ "$webui_status" = "200" ]; then
        log_info "✅ OpenWebUI is accessible after update"
    else
        log_warn "⚠️  OpenWebUI returned status: $webui_status"
    fi
    
    # Check updated version
    log_info "Checking updated version..."
    local updated_version=$(gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command="
        cd /app
        sudo docker images ghcr.io/open-webui/open-webui:main --format 'table {{.CreatedAt}}\t{{.ID}}' | grep -v CREATED | head -1
    " 2>/dev/null || echo "unknown")
    
    if [ "$updated_version" != "unknown" ]; then
        log_info "Updated version info: $updated_version"
    fi
    
    log_info "Update verification completed"
}

# Function to display final information
display_final_info() {
    EXTERNAL_IP=$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
    
    echo ""
    echo "🎉 OPEN WEBUI UPDATE COMPLETE!"
    echo "=============================="
    echo ""
    echo "VM Information:"
    echo "   Instance: $INSTANCE_NAME"
    echo "   Project: $PROJECT_ID"
    echo "   Zone: $ZONE"
    echo "   External IP: $EXTERNAL_IP"
    echo ""
    echo "🌐 Updated Access URLs:"
    echo "   OpenWebUI: http://$EXTERNAL_IP:8080"
    echo "   MCPO API:  http://$EXTERNAL_IP:8001/docs"
    echo ""
    echo "🔧 Management Commands:"
    echo "   View logs:"
    echo "     gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command='cd /app && sudo docker-compose logs -f openwebui'"
    echo ""
    echo "   Check container status:"
    echo "     gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command='cd /app && sudo docker-compose ps'"
    echo ""
    echo "   Restart if needed:"
    echo "     gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command='cd /app && sudo docker-compose restart openwebui'"
    echo ""
    echo "✅ Your OpenWebUI has been updated to the latest version!"
    echo ""
    echo "🚀 Visit http://$EXTERNAL_IP:8080 to use the updated OpenWebUI!"
}

# Main update flow
main() {
    log_info "Starting Open WebUI update process..."
    
    # Step 1: Check prerequisites
    check_prerequisites
    
    # Step 2: Get current version info
    get_current_version
    
    # Step 3: Create backup
    backup_data
    
    # Step 4: Update Open WebUI container
    update_openwebui
    
    # Step 5: Wait for services to be ready
    if wait_for_services; then
        log_info "All services are healthy after update"
    else
        log_warn "Services started but may need manual verification"
    fi
    
    # Step 6: Verify the update
    verify_update
    # Step 7: Display final information
    display_final_info
}

# Error handling
trap 'log_error "Update failed at line $LINENO. Check the error above."' ERR

# Run main update process
main "$@"


