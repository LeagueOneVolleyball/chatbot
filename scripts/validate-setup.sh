#!/bin/bash
# MCP Integration Validation Script

set -e

echo "Validating MCP Setup..."

# Function to check if required tools are available
check_requirements() {
    echo "Checking requirements..."
    
    local required_tools=("docker" "gcloud" "curl")
    local missing_tools=()
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        echo "ERROR: Missing required tools: ${missing_tools[*]}"
        echo "Please install the missing tools before proceeding."
        exit 1
    fi
    
    echo "All required tools are available"
}

# Function to validate Google Cloud configuration
check_gcloud_config() {
    echo "Checking Google Cloud configuration..."
    
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        echo "ERROR: No active Google Cloud authentication found"
        echo "Please run: gcloud auth login"
        exit 1
    fi
    
    local project_id=$(gcloud config get-value project 2>/dev/null)
    if [ -z "$project_id" ]; then
        echo "ERROR: No default project set"
        echo "Please run: gcloud config set project YOUR_PROJECT_ID"
        exit 1
    fi
    
    echo "Google Cloud configuration is valid (Project: $project_id)"
}

# Function to check secrets
check_secrets() {
    echo "Checking Google Secret Manager secrets..."
    
    local required_secrets=("openwebui-openai-api-key" "snowflake-account" "snowflake-user" "snowflake-private-key")
    local missing_secrets=()
    
    for secret in "${required_secrets[@]}"; do
        if ! gcloud secrets describe "$secret" &>/dev/null; then
            missing_secrets+=("$secret")
        fi
    done
    
    if [ ${#missing_secrets[@]} -ne 0 ]; then
        echo "WARNING: Missing secrets: ${missing_secrets[*]}"
        echo "Run './scripts/setup-secrets.sh' to create required secrets"
        return 1
    fi
    
    echo "All required secrets are configured"
}

# Function to validate Docker configuration files
check_docker_config() {
    echo "Checking Docker configuration..."
    
    if [ ! -f "Dockerfile" ]; then
        echo "ERROR: Dockerfile not found"
        exit 1
    fi
    
    if [ ! -f "docker-compose.yml" ]; then
        echo "ERROR: docker-compose.yml not found"
        exit 1
    fi
    
    # Test Docker build (basic syntax check)
    echo "Testing Dockerfile syntax..."
    if ! docker build --no-cache -t mcp-test . --dry-run 2>/dev/null; then
        echo "WARNING: Dockerfile has syntax issues (continuing anyway)"
    else
        echo "Dockerfile syntax is valid"
    fi
}

# Function to validate MCP configuration
check_mcp_config() {
    echo "Checking MCP configuration..."
    
    if [ ! -f "config/mcp-config.json" ]; then
        echo "ERROR: MCP configuration file not found"
        exit 1
    fi
    
    # Validate JSON syntax
    if ! python -m json.tool config/mcp-config.json > /dev/null 2>&1; then
        echo "ERROR: MCP configuration JSON is invalid"
        exit 1
    fi
    
    echo "MCP configuration is valid"
}

# Function to check script permissions
check_script_permissions() {
    echo "Checking script permissions..."
    
    local scripts=("scripts/start-mcp-servers.sh" "scripts/entrypoint.sh" "scripts/build-and-deploy.sh")
    
    for script in "${scripts[@]}"; do
        if [ ! -x "$script" ]; then
            echo "Making $script executable..."
            chmod +x "$script"
        fi
    done
    
    echo "All scripts have proper permissions"
}

# Function to test MCP package availability
test_mcp_package() {
    echo "Testing MCP Snowflake package availability..."
    
    # Create a temporary Docker container to test package installation
    cat > /tmp/test-mcp.Dockerfile << EOF
FROM python:3.12-slim
RUN pip install mcp_snowflake
RUN python -c "import mcp_snowflake; print('✅ mcp_snowflake package imported successfully')"
EOF
    
    if docker build -f /tmp/test-mcp.Dockerfile -t mcp-package-test /tmp >/dev/null 2>&1; then
        echo "MCP Snowflake package can be installed and imported"
        docker rmi mcp-package-test >/dev/null 2>&1
    else
        echo "WARNING: MCP Snowflake package installation test failed"
    fi
    
    rm -f /tmp/test-mcp.Dockerfile
}

# Main validation function
main() {
    echo "Starting MCP Integration Validation"
    echo "==================================="
    
    check_requirements
    echo ""
    
    check_gcloud_config
    echo ""
    
    check_secrets || echo "WARNING: Secrets not configured - run setup-secrets.sh first"
    echo ""
    
    check_docker_config
    echo ""
    
    check_mcp_config
    echo ""
    
    check_script_permissions
    echo ""
    
    test_mcp_package
    echo ""
    
    echo "==================================="
    echo "MCP Integration validation completed!"
    echo ""
    echo "Next steps:"
    echo "1. If secrets are missing, run: ./scripts/setup-secrets.sh"
    echo "2. Build and deploy: ./scripts/build-and-deploy.sh"
    echo "3. Test the deployment: ./scripts/health-check.py"
}

# Execute main function
main "$@" 