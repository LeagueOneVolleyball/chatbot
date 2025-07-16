#!/bin/bash

set -e

echo "Starting MCPO Snowflake Server..."

# Wait for secrets to be available (for Cloud Run)
if [ -f /secrets/snowflake-private-key ]; then
    echo "Using Snowflake private key from Cloud Run secret"
    export SNOWFLAKE_PRIVATE_KEY_PATH=/secrets/snowflake-private-key
elif [ -f /keys/comp_role_key.p8 ]; then
    echo "Using Snowflake private key from mounted volume"
    export SNOWFLAKE_PRIVATE_KEY_PATH=/keys/comp_role_key.p8
else
    echo "ERROR: No Snowflake private key found"
    exit 1
fi

# Validate required environment variables
required_vars=(
    "SNOWFLAKE_ACCOUNT"
    "SNOWFLAKE_USER"
    "SNOWFLAKE_WAREHOUSE"
    "SNOWFLAKE_DATABASE"
)

for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "ERROR: Required environment variable $var is not set"
        exit 1
    fi
done

echo "Environment variables validated"
echo "   Account: $SNOWFLAKE_ACCOUNT"
echo "   User: $SNOWFLAKE_USER"
echo "   Warehouse: $SNOWFLAKE_WAREHOUSE"
echo "   Database: $SNOWFLAKE_DATABASE"
echo "   Key Path: $SNOWFLAKE_PRIVATE_KEY_PATH"

# Set MCPO configuration
MCPO_PORT=${MCPO_PORT:-8001}
MCPO_HOST=${MCPO_HOST:-0.0.0.0}
MCPO_API_KEY=${MCPO_API_KEY:-${MCPO_SNOWFLAKE_API_KEY:-}}

# Validate API key for security
if [ -z "$MCPO_API_KEY" ]; then
    echo "WARNING: No MCPO API key set. Server will run without authentication!"
    echo "   Set MCPO_API_KEY or MCPO_SNOWFLAKE_API_KEY for secure access"
    API_KEY_ARGS=""
else
    echo "MCPO API key configured for secure access"
    API_KEY_ARGS="--api-key \"$MCPO_API_KEY\""
fi

echo "Starting MCPO server on $MCPO_HOST:$MCPO_PORT"
echo "Once started, visit: http://$MCPO_HOST:$MCPO_PORT/docs"

# Check if configuration file exists
if [ -f "/app/config/mcpo-config.json" ]; then
    echo "📋 Using MCPO configuration file: /app/config/mcpo-config.json"
    exec sh -c "uvx mcpo --host \"$MCPO_HOST\" --port \"$MCPO_PORT\" $API_KEY_ARGS --config /app/config/mcpo-config.json"
else
    echo "🔧 Using command-line configuration"
    # Start MCPO with Snowflake MCP server
    exec sh -c "uvx mcpo --host \"$MCPO_HOST\" --port \"$MCPO_PORT\" $API_KEY_ARGS -- uvx mcp-snowflake"
fi 