#!/bin/bash

set -e

echo "Starting Local Development Environment with MCPO"
echo "================================================"

# Check if .env file exists
if [ ! -f .env ]; then
    echo "ERROR: .env file not found. Please create one based on env.example"
    exit 1
fi

# Load environment variables
set -a
source .env
set +a

# Check required environment variables
required_vars=(
    "SNOWFLAKE_ACCOUNT"
    "SNOWFLAKE_USER"
    "SNOWFLAKE_WAREHOUSE"
    "SNOWFLAKE_DATABASE"
    "OPENAI_API_KEY"
)

for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "ERROR: Required environment variable $var is not set"
        exit 1
    fi
done

echo "Environment variables validated"

# Clean up any existing containers
echo "Cleaning up existing containers..."
docker-compose down --remove-orphans || true

# Build and start services
echo "Building and starting services..."
docker-compose build
docker-compose up -d

# Wait for services to be ready
echo "Waiting for services to be ready..."
sleep 10

# Check service status
echo "Service Status:"
echo "=============="

check_service() {
    local name=$1
    local url=$2
    local max_attempts=15
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -f -s "$url" > /dev/null 2>&1; then
            echo "$name is ready at $url"
            return 0
        fi
        
        echo "Attempt $attempt/$max_attempts: Waiting for $name..."
        sleep 2
        attempt=$((attempt + 1))
    done
    
    echo "ERROR: $name failed to start at $url"
    return 1
}

# Check MCPO Snowflake
check_service "MCPO Snowflake" "http://localhost:8001/docs"

# Check OpenWebUI
check_service "OpenWebUI" "http://localhost:8080"

echo ""
echo "Development environment is ready!"
echo "================================"
echo "MCPO Snowflake API: http://localhost:8001/docs"
echo "OpenWebUI: http://localhost:8080"
echo ""
echo "Useful commands:"
echo "   View logs: docker-compose logs -f"
echo "   Stop services: docker-compose down"
echo "   Restart services: docker-compose restart"
echo ""
echo "Test Snowflake connection:"
echo "   curl -X POST http://localhost:8001/list_databases -H 'Content-Type: application/json' -d '{}'"
echo ""
echo "Ready for development!" 