#!/bin/bash

set -e

echo "OpenWebUI + MCPO Deployment Troubleshooting"
echo "==========================================="

# Configuration
PROJECT_ID="comp-tool-poc-lovb"
ZONE="us-central1-a"
INSTANCE_NAME="openwebui-mcpo"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# Function to check VM status
check_vm_status() {
    echo "🔍 Checking VM Status"
    echo "===================="
    
    if ! gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE >/dev/null 2>&1; then
        log_error "VM $INSTANCE_NAME not found in zone $ZONE"
        echo "   Solution: Run ./scripts/deploy-gcp-vm.sh to create the VM"
        return 1
    fi
    
    local vm_status=$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format='get(status)')
    local external_ip=$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
    
    log_info "VM Status: $vm_status"
    log_info "External IP: $external_ip"
    
    if [ "$vm_status" != "RUNNING" ]; then
        log_warn "VM is not running. Starting VM..."
        gcloud compute instances start $INSTANCE_NAME --zone=$ZONE
        log_info "VM started. Waiting for it to be ready..."
        sleep 30
    fi
    
    echo ""
}

# Function to check Docker services
check_docker_services() {
    echo "🐳 Checking Docker Services"
    echo "=========================="
    
    log_info "Connecting to VM to check Docker status..."
    
    gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command="
        echo 'Docker service status:'
        sudo systemctl status docker --no-pager | head -3
        echo ''
        echo 'Docker compose services:'
        cd /app && sudo docker-compose ps || echo 'No compose services found'
    " || {
        log_error "Failed to connect to VM or check Docker status"
        return 1
    }
    
    echo ""
}

# Function to check file permissions
check_file_permissions() {
    echo "🔐 Checking File Permissions"
    echo "=========================="
    
    log_info "Checking file permissions on VM..."
    
    gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command="
        echo 'Application directory ownership:'
        ls -la /app/ | head -5
        echo ''
        echo 'Environment file permissions:'
        ls -la /app/.env 2>/dev/null || echo '.env file not found'
        echo ''
        echo 'Private key permissions:'
        ls -la /app/keys/comp_role_key.p8 2>/dev/null || echo 'Private key not found'
        echo ''
        echo 'Logs directory permissions:'
        ls -la /app/logs/ 2>/dev/null || echo 'Logs directory not found'
    " || {
        log_error "Failed to check file permissions"
        return 1
    }
    
    echo ""
}

# Function to fix common permission issues
fix_permissions() {
    echo "🔧 Fixing File Permissions"
    echo "========================="
    
    log_info "Fixing file permissions for Docker containers..."
    
    gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command="
        cd /app
        
        # Fix ownership for Docker containers (UID 1001 = appuser)
        sudo chown -R 1001:1001 /app
        
        # Fix specific file permissions
        if [ -f .env ]; then
            sudo chmod 644 .env
            echo 'Fixed .env permissions'
        fi
        
        if [ -f keys/comp_role_key.p8 ]; then
            sudo chmod 644 keys/comp_role_key.p8
            echo 'Fixed private key permissions'
        fi
        
        # Fix directory permissions
        sudo chmod 755 logs/ keys/ 2>/dev/null || true
        
        echo 'File permissions fixed'
    " || {
        log_error "Failed to fix file permissions"
        return 1
    }
    
    log_info "File permissions have been fixed"
    echo ""
}

# Function to check and restart services
restart_services() {
    echo "🚀 Restarting Services"
    echo "===================="
    
    log_info "Stopping existing services..."
    
    gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command="
        cd /app
        sudo docker-compose down --remove-orphans || true
        sudo docker system prune -f || true
    " || log_warn "Failed to stop services (may not be running)"
    
    log_info "Starting services with proper permissions..."
    
    gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command="
        cd /app
        sudo docker-compose build
        sudo docker-compose up -d
    " || {
        log_error "Failed to start services"
        return 1
    }
    
    log_info "Services restarted. Waiting for health checks..."
    sleep 30
    
    echo ""
}

# Function to check service health
check_service_health() {
    echo "❤️ Checking Service Health"
    echo "========================="
    
    # Get VM external IP
    local external_ip=$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
    
    log_info "External IP: $external_ip"
    
    # Check MCPO API
    log_info "Testing MCPO API..."
    local mcpo_status=$(curl -s -o /dev/null -w "%{http_code}" "http://$external_ip:8001/docs" 2>/dev/null || echo "000")
    if [ "$mcpo_status" = "200" ]; then
        log_info "✅ MCPO API is healthy (HTTP $mcpo_status)"
    else
        log_warn "⚠️  MCPO API issue (HTTP $mcpo_status)"
    fi
    
    # Check OpenWebUI
    log_info "Testing OpenWebUI..."
    local webui_status=$(curl -s -o /dev/null -w "%{http_code}" "http://$external_ip:8080" 2>/dev/null || echo "000")
    if [ "$webui_status" = "200" ]; then
        log_info "✅ OpenWebUI is healthy (HTTP $webui_status)"
    else
        log_warn "⚠️  OpenWebUI issue (HTTP $webui_status)"
    fi
    
    # Check Docker container health
    log_info "Checking Docker container health..."
    gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command="
        cd /app
        echo 'Container Status:'
        sudo docker-compose ps
        echo ''
        echo 'Recent logs (last 10 lines):'
        sudo docker-compose logs --tail=10
    " || log_warn "Failed to get container status"
    
    echo ""
}

# Function to display service URLs and management commands
display_info() {
    local external_ip=$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
    
    echo "📋 Service Information"
    echo "====================="
    echo ""
    echo "🌐 Access URLs:"
    echo "   OpenWebUI: http://$external_ip:8080"
    echo "   MCPO API:  http://$external_ip:8001/docs"
    echo ""
    echo "🔧 Management Commands:"
    echo "   Connect to VM:"
    echo "     gcloud compute ssh $INSTANCE_NAME --zone=$ZONE"
    echo ""
    echo "   View all logs:"
    echo "     gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command='cd /app && sudo docker-compose logs -f'"
    echo ""
    echo "   View specific service logs:"
    echo "     gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command='cd /app && sudo docker-compose logs -f mcpo-tools'"
    echo "     gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command='cd /app && sudo docker-compose logs -f openwebui'"
    echo ""
    echo "   Restart services:"
    echo "     gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command='cd /app && sudo docker-compose restart'"
    echo ""
    echo "   Full redeploy:"
    echo "     ./scripts/deploy-app-to-vm.sh"
    echo ""
}

# Function for interactive troubleshooting menu
interactive_menu() {
    echo "🛠️ Interactive Troubleshooting Menu"
    echo "=================================="
    echo ""
    echo "What would you like to do?"
    echo "1. Check VM and service status"
    echo "2. Fix file permissions"
    echo "3. Restart services"
    echo "4. Full health check"
    echo "5. View recent logs"
    echo "6. Connect to VM"
    echo "7. Exit"
    echo ""
    
    read -p "Select option (1-7): " choice
    
    case $choice in
        1)
            check_vm_status
            check_docker_services
            ;;
        2)
            fix_permissions
            ;;
        3)
            restart_services
            ;;
        4)
            check_vm_status
            check_docker_services
            check_file_permissions
            check_service_health
            ;;
        5)
            gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command="cd /app && sudo docker-compose logs --tail=50"
            ;;
        6)
            echo "Connecting to VM... (type 'exit' to return)"
            gcloud compute ssh $INSTANCE_NAME --zone=$ZONE
            ;;
        7)
            echo "Goodbye!"
            exit 0
            ;;
        *)
            log_warn "Invalid option. Please select 1-7."
            interactive_menu
            ;;
    esac
}

# Main function
main() {
    log_info "Starting deployment troubleshooting..."
    echo ""
    
    # Check if running in interactive mode
    if [ "$1" = "--interactive" ] || [ "$1" = "-i" ]; then
        while true; do
            interactive_menu
            echo ""
            read -p "Continue troubleshooting? (y/n): " continue_choice
            if [[ "$continue_choice" != "y" && "$continue_choice" != "Y" ]]; then
                break
            fi
            echo ""
        done
    else
        # Run full diagnostic
        check_vm_status
        check_docker_services
        check_file_permissions
        check_service_health
        display_info
    fi
    
    echo "🎉 Troubleshooting complete!"
}

# Help function
show_help() {
    echo "OpenWebUI + MCPO Deployment Troubleshooting Script"
    echo ""
    echo "Usage:"
    echo "  $0                  - Run full diagnostic"
    echo "  $0 --interactive    - Interactive troubleshooting menu"
    echo "  $0 --help          - Show this help"
    echo ""
    echo "This script helps diagnose and fix common deployment issues:"
    echo "  - VM status and connectivity"
    echo "  - Docker service health"
    echo "  - File permission issues"
    echo "  - Container health checks"
    echo "  - Service accessibility"
    echo ""
}

# Check command line arguments
case "${1:-}" in
    --help|-h)
        show_help
        exit 0
        ;;
    --interactive|-i)
        main --interactive
        ;;
    *)
        main
        ;;
esac 