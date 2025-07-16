#!/bin/bash

set -e

echo "Starting MCPO Snowflake Server (Local Development)"
echo "=================================================="

# Set the correct Snowflake account (without duplication)
export SNOWFLAKE_ACCOUNT="UPNOBVJ-OK59235"
export SNOWFLAKE_USER="COMP_SERVICE_ACCOUNT"
export SNOWFLAKE_PRIVATE_KEY_PATH="/Users/kevin/dev/keys/comp_role_key.p8"
export SNOWFLAKE_PRIVATE_KEY_PASSPHRASE=""
export SNOWFLAKE_WAREHOUSE="COMP_ROLE_WH"
export SNOWFLAKE_DATABASE="SILVER_DB"
export SNOWFLAKE_SCHEMA="PUBLIC"
export SNOWFLAKE_ROLE="COMP_ROLE"
export SNOWFLAKE_CONN_REFRESH_HOURS="8"

# MCPO Configuration
export MCPO_API_KEY=${MCPO_API_KEY:-"local-dev-key-2024"}
export MCPO_PORT=${MCPO_PORT:-8000}
export MCPO_HOST=${MCPO_HOST:-"0.0.0.0"}

# Validate required environment variables
required_vars=(
    "SNOWFLAKE_ACCOUNT"
    "SNOWFLAKE_USER"
    "SNOWFLAKE_WAREHOUSE"
    "SNOWFLAKE_DATABASE"
    "SNOWFLAKE_PRIVATE_KEY_PATH"
)

for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "ERROR: Required environment variable $var is not set"
        exit 1
    fi
done

# Check if private key file exists
if [ ! -f "$SNOWFLAKE_PRIVATE_KEY_PATH" ]; then
    echo "ERROR: Private key file not found at: $SNOWFLAKE_PRIVATE_KEY_PATH"
    exit 1
fi

echo "All required Snowflake environment variables are set"
echo "Private key file found: $SNOWFLAKE_PRIVATE_KEY_PATH"
echo "MCPO API Key: $MCPO_API_KEY"
echo "Starting MCPO with Snowflake MCP server..."
echo "   Account: $SNOWFLAKE_ACCOUNT"
echo "   User: $SNOWFLAKE_USER"
echo "   Warehouse: $SNOWFLAKE_WAREHOUSE"
echo "   Database: $SNOWFLAKE_DATABASE"
echo ""
echo "Once started, visit: http://localhost:$MCPO_PORT/docs"
echo "API Key required for requests: $MCPO_API_KEY"
echo "Test commands:"
echo "   curl -H 'Authorization: Bearer $MCPO_API_KEY' http://localhost:$MCPO_PORT/tools/list"
echo "   curl -X POST -H 'Authorization: Bearer $MCPO_API_KEY' -H 'Content-Type: application/json' \\"
echo "        http://localhost:$MCPO_PORT/tools/call \\"
echo "        -d '{\"name\": \"execute_query\", \"arguments\": {\"query\": \"SELECT CURRENT_TIMESTAMP()\"}}'"
echo "🛑 Press Ctrl+C to stop"
echo ""

# Start MCPO with Snowflake MCP server
exec uvx mcpo --host "$MCPO_HOST" --port "$MCPO_PORT" --api-key "$MCPO_API_KEY" -- uvx mcp-snowflake 