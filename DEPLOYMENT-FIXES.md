# Deployment Script Fixes Summary

## Overview
This document summarizes the fixes applied to the deployment scripts based on issues encountered during the first cloud deployment attempt.

## Issues Encountered

### 1. **Permission Problems** ❌
**Problem**: Docker containers couldn't read files due to incorrect ownership and permissions
- Private key files owned by `root:root` with `600` permissions
- Environment files with `600` permissions
- Container running as `appuser` (UID 1001) couldn't access files

**Root Cause**: Files uploaded to VM were owned by root, but Docker containers run as `appuser` (UID 1001)

### 2. **Interactive Input Blocking** ❌ 
**Problem**: Deployment script would freeze waiting for user input
- Script prompted for OpenAI API key, passphrase, etc.
- No timeout or default handling
- Manual intervention required mid-deployment

**Root Cause**: Script designed for interactive use, not automated deployment

### 3. **Environment Configuration Issues** ❌
**Problem**: Environment variables not properly configured for VM deployment
- Local `.env` file had local paths and URLs
- VM needed different paths (`/app/keys/` instead of local paths)
- External IP needed to be dynamically determined

### 4. **Poor Error Handling** ❌
**Problem**: Scripts failed silently or with unclear error messages
- No validation of prerequisites
- No recovery mechanisms
- Difficult to debug when things went wrong

### 5. **Missing Health Checks** ❌
**Problem**: No proper verification that services started correctly
- No waiting for container health checks
- No verification of service accessibility
- Scripts completed even if services failed to start

## Fixes Applied

### 1. **Fixed File Permissions** ✅

#### `scripts/deploy-app-to-vm.sh`
```bash
# NEW: Proper permission handling for Docker containers
upload_private_key() {
    # Upload key to user home directory first
    gcloud compute scp "$KEY_PATH" $INSTANCE_NAME:/home/$(whoami)/comp_role_key.p8 --zone=$ZONE
    
    # Move to correct location with proper permissions for Docker container
    gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command="
        sudo mv /home/$(whoami)/comp_role_key.p8 /app/keys/
        sudo chown 1001:1001 /app/keys/comp_role_key.p8    # UID 1001 = appuser
        sudo chmod 644 /app/keys/comp_role_key.p8           # Readable by container
    "
}

create_vm_env() {
    # Create environment file with proper permissions
    gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command="
        sudo mv /home/$(whoami)/.env /app/.env
        sudo chown 1001:1001 /app/.env                      # UID 1001 = appuser  
        sudo chmod 644 /app/.env                            # Readable by container
    "
}
```

#### `scripts/upload-to-vm.sh`
```bash
# NEW: Set ownership for Docker compatibility
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command="
    # Set ownership to appuser (UID 1001) for Docker compatibility
    sudo chown -R 1001:1001 /app
    
    # Set proper permissions for directories
    sudo chmod 755 /app/logs /app/keys
"
```

### 2. **Eliminated Interactive Prompts** ✅

#### Before (❌)
```bash
# OLD: Interactive prompts that blocked deployment
read -p "OpenAI API Key: " OPENAI_API_KEY
read -s -p "Snowflake Private Key Passphrase (hidden): " SNOWFLAKE_PRIVATE_KEY_PASSPHRASE
```

#### After (✅)
```bash
# NEW: Use local .env file automatically
validate_local_env() {
    # Source the .env file and check required variables
    set -a
    source .env
    set +a
    
    # Check required variables are present
    local required_vars=("OPENAI_API_KEY" "SNOWFLAKE_ACCOUNT" "SNOWFLAKE_USER")
    # ... validation logic
}
```

### 3. **Fixed Environment Configuration** ✅

#### Before (❌)
```bash
# OLD: Hardcoded environment creation
ENV_CONTENT="SNOWFLAKE_PRIVATE_KEY_PATH=/app/keys/comp_role_key.p8
WEBUI_URL=http://EXTERNAL_IP:8080"
```

#### After (✅)
```bash
# NEW: Dynamic environment file creation from local .env
create_vm_env() {
    # Get VM external IP dynamically
    EXTERNAL_IP=$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
    
    # Copy local .env and update VM-specific values
    sed "s|WEBUI_URL=.*|WEBUI_URL=http://$EXTERNAL_IP:8080|g" .env > "$temp_env"
    sed -i "s|SNOWFLAKE_PRIVATE_KEY_PATH=.*|SNOWFLAKE_PRIVATE_KEY_PATH=/app/keys/comp_role_key.p8|g" "$temp_env"
}
```

### 4. **Added Comprehensive Error Handling** ✅

#### New Features:
```bash
# Colored logging functions
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Error trap for debugging
trap 'log_error "Deployment failed at line $LINENO. Check the error above."' ERR

# Prerequisite checking
check_prerequisites() {
    # Check gcloud CLI, authentication, project, local files
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI not found. Please install Google Cloud SDK"
        exit 1
    fi
    # ... more checks
}

# Robust function calls with error handling
upload_private_key() {
    gcloud compute scp "$KEY_PATH" $INSTANCE_NAME:/home/$(whoami)/comp_role_key.p8 --zone=$ZONE || {
        log_error "Failed to upload private key"
        exit 1
    }
}
```

### 5. **Added Proper Health Checks** ✅

#### New Service Health Monitoring:
```bash
start_services() {
    # Start services
    sudo docker-compose up -d
    
    # Wait for services to be ready with timeout
    local max_attempts=20
    while [ $attempt -le $max_attempts ]; do
        local mcpo_healthy=$(sudo docker-compose ps mcpo-tools --format json | jq -r '.[0].Health // "unknown"')
        local openwebui_healthy=$(sudo docker-compose ps openwebui --format json | jq -r '.[0].Health // "unknown"')
        
        if [[ "$mcpo_healthy" == "healthy" && "$openwebui_healthy" == "healthy" ]]; then
            log_info "All services are healthy!"
            break
        fi
        
        sleep 15
        ((attempt++))
    done
}

verify_deployment() {
    # Test actual HTTP endpoints
    local mcpo_status=$(curl -s -o /dev/null -w "%{http_code}" "http://$EXTERNAL_IP:8001/docs")
    local webui_status=$(curl -s -o /dev/null -w "%{http_code}" "http://$EXTERNAL_IP:8080")
    
    if [ "$mcpo_status" = "200" ]; then
        log_info "✅ MCPO API is accessible"
    else
        log_warn "⚠️  MCPO API returned status: $mcpo_status"
    fi
}
```

### 6. **Fixed Validation Script** ✅

#### Fixed Bash Syntax Issue:
```bash
# OLD: Bash syntax error with variable checking
if [ -z "${!var+x}" ] || [ "${!var}" = "your-${var_lower}-here" ]; then

# NEW: Proper variable existence checking
if ! declare -p "$var" >/dev/null 2>&1 || [ "${!var}" = "your-${var_lower}-here" ]; then
```

### 7. **Created Robust VM Service Script** ✅

#### New `start-services.sh` on VM:
```bash
# Comprehensive service startup with proper permission handling
check_prerequisites() {
    # Check and fix file permissions for Docker containers
    sudo chown 1001:1001 keys/comp_role_key.p8
    sudo chmod 644 keys/comp_role_key.p8
    sudo chown 1001:1001 .env
    sudo chmod 644 .env
}

wait_for_services() {
    # Proper health check monitoring
    local max_attempts=24  # 6 minutes total
    while [ $attempt -le $max_attempts ]; do
        # Check container health status
        # Wait for both services to be healthy
        # Provide detailed status updates
    done
}
```

## New Scripts Created

### 1. **`scripts/troubleshoot-deployment.sh`** 🆕
- Comprehensive diagnostic tool
- Interactive troubleshooting menu
- Automated permission fixing
- Service health monitoring
- Easy VM connection and log viewing

#### Usage:
```bash
# Full diagnostic
./scripts/troubleshoot-deployment.sh

# Interactive menu
./scripts/troubleshoot-deployment.sh --interactive

# Get help
./scripts/troubleshoot-deployment.sh --help
```

## Deployment Flow Comparison

### Before (❌)
1. Run script
2. Script freezes waiting for input
3. Manual intervention required
4. Services start but permissions broken
5. Containers fail with permission errors
6. Manual debugging required

### After (✅)
1. `./scripts/deploy-app-to-vm.sh` - One command
2. Automatic validation and error checking
3. Uses local `.env` file automatically
4. Proper file permissions set for containers
5. Health checks ensure services are ready
6. Clear status reporting and access URLs

## Key Benefits of Fixes

### 🚀 **Reliability**
- Automated deployment without manual intervention
- Comprehensive error handling and recovery
- Proper validation at each step

### 🔒 **Security**  
- Correct file permissions for Docker containers
- Secure key handling and storage
- Proper user/group ownership

### 🛠️ **Maintainability**
- Clear, colored logging for easy debugging
- Modular functions for each deployment step
- Comprehensive troubleshooting tools

### 📊 **Visibility**
- Real-time health checks and status reporting
- Clear access URLs and management commands
- Detailed error messages and recovery suggestions

## Testing Recommendations

### Before Each Release:
1. **Clean VM Test**: Deploy to fresh VM to test full flow
2. **Permission Test**: Verify all containers can read required files
3. **Health Check Test**: Ensure all services start and become healthy
4. **Network Test**: Verify external accessibility of services

### Validation Commands:
```bash
# 1. Validate local setup
./scripts/validate-setup.sh

# 2. Deploy to cloud
./scripts/deploy-app-to-vm.sh

# 3. Troubleshoot if needed
./scripts/troubleshoot-deployment.sh

# 4. Monitor services
gcloud compute ssh openwebui-mcpo --zone=us-central1-a --command="cd /app && sudo docker-compose logs -f"
```

## Summary

These fixes transform the deployment from a fragile, manual process to a robust, automated system that handles the most common failure modes we encountered. The key improvements are:

1. **No more permission issues** - Files have correct ownership for Docker containers
2. **No more hanging on input** - Uses local environment automatically  
3. **Proper error handling** - Clear error messages and recovery suggestions
4. **Health monitoring** - Verifies services are actually working
5. **Easy troubleshooting** - Comprehensive diagnostic and fix tools

The deployment is now ready for reliable cloud operations! 🎉 