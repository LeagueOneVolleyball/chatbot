#!/bin/bash
#
# validate-setup.sh
# Validate OpenWebUI + MCPO setup configuration
#
# Usage: ./scripts/validate-setup.sh [--fix]
#
# Options:
#   --fix    Attempt to fix common issues automatically
#
# Requirements:
#   - Docker and Docker Compose installed
#   - Environment variables configured

set -euo pipefail

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly LOG_PREFIX="[$SCRIPT_NAME]"

# Configuration
FIX_MODE=false

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "$LOG_PREFIX $*" >&2
}

log_info() {
    echo -e "$LOG_PREFIX ${BLUE}INFO:${NC} $*" >&2
}

log_success() {
    echo -e "$LOG_PREFIX ${GREEN}SUCCESS:${NC} $*" >&2
}

log_warning() {
    echo -e "$LOG_PREFIX ${YELLOW}WARNING:${NC} $*" >&2
}

log_error() {
    echo -e "$LOG_PREFIX ${RED}ERROR:${NC} $*" >&2
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check required tools
check_required_tools() {
    log_info "Checking required tools..."
    
    local missing_tools=()
    
    if ! command_exists docker; then
        missing_tools+=("docker")
    fi
    
    if ! command_exists docker-compose; then
        missing_tools+=("docker-compose")
    fi
    
    if ! command_exists curl; then
        missing_tools+=("curl")
    fi
    
    if [ ${#missing_tools[@]} -eq 0 ]; then
        log_success "All required tools are installed"
        return 0
    else
        log_error "Missing required tools: ${missing_tools[*]}"
        log "Please install the missing tools before proceeding"
        return 1
    fi
}

# Function to check Docker service
check_docker_service() {
    log_info "Checking Docker service..."
    
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker is not running or accessible"
        log "Please start Docker service and ensure current user has permissions"
        return 1
    fi
    
    log_success "Docker service is running"
    return 0
}

# Function to validate environment file
validate_environment() {
    log_info "Validating environment configuration..."
    
    # Check if .env exists
    if [ ! -f .env ]; then
        log_warning ".env file not found"
        if [ "$FIX_MODE" = true ] && [ -f env.example ]; then
            log_info "Creating .env from env.example..."
            cp env.example .env
            log_warning "Please edit .env with your actual values"
        else
            log "Please copy env.example to .env and configure your values"
            return 1
        fi
    fi
    
    # Source environment file
    set -a
    source .env
    set +a
    
    # Check required variables
    local required_vars=(
        "OPENAI_API_KEY"
        "SNOWFLAKE_ACCOUNT"
        "SNOWFLAKE_USER"
        "SNOWFLAKE_PRIVATE_KEY_PASSPHRASE"
        "MCPO_SNOWFLAKE_API_KEY"
    )
    
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        local var_lower
        var_lower=$(echo "$var" | tr '[:upper:]' '[:lower:]')
        # Special case: SNOWFLAKE_PRIVATE_KEY_PASSPHRASE can be empty (no passphrase)
        if [ "$var" = "SNOWFLAKE_PRIVATE_KEY_PASSPHRASE" ]; then
            # Check if it's set (even if empty) and not a placeholder
            if ! declare -p "$var" >/dev/null 2>&1 || [ "${!var}" = "your-${var_lower}-here" ] || [ "${!var}" = "your-${var_lower}" ]; then
                missing_vars+=("$var")
            fi
        else
            # Regular validation for other variables
            if [ -z "${!var:-}" ] || [ "${!var}" = "your-${var_lower}-here" ] || [ "${!var}" = "your-${var_lower}" ]; then
                missing_vars+=("$var")
            fi
        fi
    done
    
    if [ ${#missing_vars[@]} -eq 0 ]; then
        log_success "Environment variables are configured"
        return 0
    else
        log_error "Missing or placeholder environment variables: ${missing_vars[*]}"
        log "Please configure these variables in your .env file"
        return 1
    fi
}

# Function to check file permissions
check_file_permissions() {
    log_info "Checking file permissions..."
    
    local issues=()
    
    # Check script executability
    local scripts=(
        "scripts/deploy-gcp-vm.sh"
        "scripts/deploy-app-to-vm.sh"
        "scripts/upload-to-vm.sh"
        "scripts/validate-setup.sh"
    )
    
    for script in "${scripts[@]}"; do
        if [ -f "$script" ] && [ ! -x "$script" ]; then
            if [ "$FIX_MODE" = true ]; then
                log_info "Making $script executable..."
                chmod +x "$script"
            else
                issues+=("$script is not executable")
            fi
        fi
    done
    
    # Check logs directory
    if [ ! -d logs ]; then
        if [ "$FIX_MODE" = true ]; then
            log_info "Creating logs directory..."
            mkdir -p logs
        else
            issues+=("logs directory does not exist")
        fi
    fi
    
    # Check config directory
    if [ ! -d config ]; then
        if [ "$FIX_MODE" = true ]; then
            log_info "Creating config directory..."
            mkdir -p config
        else
            issues+=("config directory does not exist")
        fi
    fi
    
    if [ ${#issues[@]} -eq 0 ]; then
        log_success "File permissions are correct"
        return 0
    else
        log_error "Permission issues found:"
        printf '%s\n' "${issues[@]}" | sed 's/^/    /'
        return 1
    fi
}

# Function to validate Docker configuration
validate_docker_config() {
    log_info "Validating Docker configuration..."
    
    # Check if docker-compose.yml exists
    if [ ! -f docker-compose.yml ]; then
        log_error "docker-compose.yml not found"
        return 1
    fi
    
    # Validate docker-compose syntax
    if ! docker-compose config >/dev/null 2>&1; then
        log_error "docker-compose.yml has syntax errors"
        log "Run 'docker-compose config' to see detailed errors"
        return 1
    fi
    
    # Check Dockerfile existence
    if [ ! -f Dockerfile.openwebui ]; then
        log_error "Dockerfile.openwebui not found"
        return 1
    fi
    
    if [ ! -f Dockerfile.mcpo ]; then
        log_error "Dockerfile.mcpo not found"
        return 1
    fi
    
    log_success "Docker configuration is valid"
    return 0
}

# Function to check network connectivity
check_network_connectivity() {
    log_info "Checking network connectivity..."
    
    local endpoints=(
        "https://api.openai.com"
        "https://hub.docker.com"
        "https://pypi.org"
    )
    
    local failed_endpoints=()
    
    for endpoint in "${endpoints[@]}"; do
        if ! curl -s --connect-timeout 5 "$endpoint" >/dev/null; then
            failed_endpoints+=("$endpoint")
        fi
    done
    
    if [ ${#failed_endpoints[@]} -eq 0 ]; then
        log_success "Network connectivity is working"
        return 0
    else
        log_warning "Cannot reach some endpoints: ${failed_endpoints[*]}"
        log "This may cause issues during deployment"
        return 1
    fi
}

# Function to validate configuration consistency
validate_config_consistency() {
    log_info "Validating configuration consistency..."
    
    local issues=()
    
    # Source environment if available
    if [ -f .env ]; then
        set -a
        source .env
        set +a
    fi
    
    # Check port consistency
    local compose_openwebui_port
    local compose_mcpo_port
    
    compose_openwebui_port=$(grep -A 10 "openwebui:" docker-compose.yml | grep "8080:" | cut -d'"' -f2 | cut -d':' -f1 || echo "8080")
    compose_mcpo_port=$(grep -A 10 "mcpo-tools:" docker-compose.yml | grep "8001:" | cut -d'"' -f2 | cut -d':' -f1 || echo "8001")
    
    if [ "${PORT:-8080}" != "$compose_openwebui_port" ]; then
        issues+=("PORT mismatch between .env (${PORT:-8080}) and docker-compose.yml ($compose_openwebui_port)")
    fi
    
    if [ "${MCPO_SNOWFLAKE_PORT:-8001}" != "$compose_mcpo_port" ]; then
        issues+=("MCPO_SNOWFLAKE_PORT mismatch between .env (${MCPO_SNOWFLAKE_PORT:-8001}) and docker-compose.yml ($compose_mcpo_port)")
    fi
    
    if [ ${#issues[@]} -eq 0 ]; then
        log_success "Configuration is consistent"
        return 0
    else
        log_error "Configuration inconsistencies found:"
        printf '%s\n' "${issues[@]}" | sed 's/^/    /'
        return 1
    fi
}

# Function to run comprehensive validation
run_validation() {
    log "Starting comprehensive validation..."
    log "=================================="
    
    local total_checks=0
    local passed_checks=0
    local failed_checks=()
    
    # Define all checks
    local checks=(
        "check_required_tools:Required tools"
        "check_docker_service:Docker service"
        "validate_environment:Environment configuration"
        "check_file_permissions:File permissions"
        "validate_docker_config:Docker configuration"
        "check_network_connectivity:Network connectivity"
        "validate_config_consistency:Configuration consistency"
    )
    
    # Run each check
    for check in "${checks[@]}"; do
        local func_name="${check%%:*}"
        local check_name="${check##*:}"
        
        total_checks=$((total_checks + 1))
        
        if $func_name; then
            passed_checks=$((passed_checks + 1))
        else
            failed_checks+=("$check_name")
        fi
        
        echo # Add spacing between checks
    done
    
    # Summary
    log "Validation Summary"
    log "=================="
    log_info "Total checks: $total_checks"
    log_success "Passed: $passed_checks"
    
    if [ ${#failed_checks[@]} -gt 0 ]; then
        log_error "Failed: ${#failed_checks[@]}"
        log "Failed checks:"
        printf '%s\n' "${failed_checks[@]}" | sed 's/^/    /'
        
        if [ "$FIX_MODE" = false ]; then
            log ""
            log "Run with --fix to attempt automatic fixes for some issues"
        fi
        
        return 1
    else
        log_success "All validation checks passed!"
        log ""
        log "Your setup is ready for deployment!"
        return 0
    fi
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Validate OpenWebUI + MCPO setup configuration

OPTIONS:
    --fix       Attempt to fix common issues automatically
    --help      Show this help message

EXAMPLES:
    $SCRIPT_NAME                # Run validation checks
    $SCRIPT_NAME --fix         # Run validation and fix issues

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --fix)
                FIX_MODE=true
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Main function
main() {
    parse_arguments "$@"
    
    if [ "$FIX_MODE" = true ]; then
        log_info "Running validation with automatic fixes enabled"
    fi
    
    run_validation
}

# Execute main function
main "$@" 