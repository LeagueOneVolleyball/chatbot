#!/bin/bash

set -e

echo "Adding New MCPO Server"
echo "======================"

# Check if server name is provided
if [ -z "$1" ]; then
    echo "ERROR: Usage: $0 <server-name> [port] [mcp-command]"
    echo ""
    echo "Examples:"
    echo "   $0 github 8002 'uvx mcp-server-github'"
    echo "   $0 filesystem 8003 'uvx mcp-server-filesystem'"
    echo "   $0 postgres 8004 'uvx mcp-server-postgres'"
    echo ""
    echo "Available MCP servers:"
    echo "   - mcp-server-github (GitHub integration)"
    echo "   - mcp-server-filesystem (File system access)"
    echo "   - mcp-server-postgres (PostgreSQL database)"
    echo "   - mcp-server-sqlite (SQLite database)"
    echo "   - mcp-server-fetch (HTTP requests)"
    echo "   - mcp-server-brave-search (Web search)"
    exit 1
fi

SERVER_NAME="$1"
SERVER_PORT="${2:-8002}"
MCP_COMMAND="${3:-uvx mcp-server-$SERVER_NAME}"

echo "Configuration:"
echo "   Server Name: $SERVER_NAME"
echo "   Port: $SERVER_PORT"
echo "   MCP Command: $MCP_COMMAND"

# Update docker-compose.mcpo.yml
echo "Updating docker-compose.mcpo.yml..."

# Check if the server already exists
if grep -q "mcpo-$SERVER_NAME:" docker-compose.mcpo.yml; then
    echo "WARNING: Server mcpo-$SERVER_NAME already exists in docker-compose.mcpo.yml"
    echo "   Please remove it first or choose a different name."
    exit 1
fi

# Add the new server to docker-compose.mcpo.yml
cat >> docker-compose.mcpo.yml << EOF

  # MCPO $SERVER_NAME Server
  mcpo-$SERVER_NAME:
    build:
      context: .
      dockerfile: Dockerfile.mcpo
    ports:
      - "$SERVER_PORT:$SERVER_PORT"
    environment:
      - MCPO_PORT=$SERVER_PORT
      - MCPO_HOST=0.0.0.0
    volumes:
      - ./logs:/var/log/mcpo
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:$SERVER_PORT/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    restart: unless-stopped
    networks:
      - openwebui-network
    command: >
      sh -c "
        echo 'Starting MCPO $SERVER_NAME Server on port $SERVER_PORT...' &&
        uvx mcpo --host 0.0.0.0 --port $SERVER_PORT -- $MCP_COMMAND
      "
EOF

echo "Added mcpo-$SERVER_NAME service to docker-compose.mcpo.yml"

# Update OpenWebUI environment variables
echo "Updating OpenWebUI configuration..."

# Update the MCPO_SERVERS environment variable
if grep -q "MCPO_SERVERS=" docker-compose.mcpo.yml; then
    # Append to existing MCPO_SERVERS
    sed -i.bak "s/MCPO_SERVERS=snowflake:http:\/\/mcpo-snowflake:8001/MCPO_SERVERS=snowflake:http:\/\/mcpo-snowflake:8001,$SERVER_NAME:http:\/\/mcpo-$SERVER_NAME:$SERVER_PORT/" docker-compose.mcpo.yml
else
    # This shouldn't happen, but just in case
    echo "WARNING: MCPO_SERVERS not found in docker-compose.mcpo.yml"
fi

# Add dependency to OpenWebUI service
sed -i.bak "/depends_on:/a\\
      mcpo-$SERVER_NAME:\\
        condition: service_healthy" docker-compose.mcpo.yml

echo "Updated OpenWebUI configuration"

# Create startup script for the new server
echo "Creating startup script..."

cat > "scripts/start-mcpo-$SERVER_NAME.sh" << EOF
#!/bin/bash

set -e

echo "🚀 Starting MCPO $SERVER_NAME Server..."

# Add any server-specific environment variable validation here
# Example for GitHub:
# if [ "$SERVER_NAME" = "github" ]; then
#     if [ -z "\$GITHUB_TOKEN" ]; then
#         echo "❌ GITHUB_TOKEN environment variable is required for GitHub MCP server"
#         exit 1
#     fi
# fi

# Set default port if not specified
MCPO_PORT=\${MCPO_PORT:-$SERVER_PORT}
MCPO_HOST=\${MCPO_HOST:-0.0.0.0}

echo "🌐 Starting MCPO server on \$MCPO_HOST:\$MCPO_PORT"

# Start MCPO with $SERVER_NAME MCP server
exec uvx mcpo --host "\$MCPO_HOST" --port "\$MCPO_PORT" -- $MCP_COMMAND
EOF

chmod +x "scripts/start-mcpo-$SERVER_NAME.sh"

echo "Created scripts/start-mcpo-$SERVER_NAME.sh"

# Update Cloud Run configuration
echo "Updating Cloud Run configuration..."

# Add supervisor configuration for the new server
cat >> "config/supervisord-cloudrun.conf" << EOF

[program:mcpo-$SERVER_NAME]
command=/app/start-mcpo-$SERVER_NAME.sh
directory=/app
user=appuser
autostart=true
autorestart=true
stderr_logfile=/var/log/mcpo/mcpo-$SERVER_NAME.log
stdout_logfile=/var/log/mcpo/mcpo-$SERVER_NAME.log
environment=HOME="/home/appuser",USER="appuser",PYTHONPATH="/app"
priority=1$(printf "%02d" $((SERVER_PORT - 8000)))
startsecs=10
startretries=3
EOF

echo "Updated supervisor configuration"

# Update Cloud Run Dockerfile
echo "Updating Cloud Run Dockerfile..."

# Add the new startup script to the Dockerfile
sed -i.bak "/COPY scripts\/start-mcpo-snowflake.sh/a\\
COPY scripts/start-mcpo-$SERVER_NAME.sh /app/start-mcpo-$SERVER_NAME.sh" Dockerfile.cloudrun

# Make the script executable
sed -i.bak "/RUN chmod +x.*start-mcpo-snowflake.sh/a\\
RUN chmod +x /app/start-mcpo-$SERVER_NAME.sh" Dockerfile.cloudrun

echo "Updated Cloud Run Dockerfile"

# Update environment file template
echo "Updating environment template..."

cat >> env.example << EOF

# $SERVER_NAME MCP Server Configuration
# Add any required environment variables for $SERVER_NAME here
# Example: ${SERVER_NAME^^}_API_KEY=your-api-key-here
EOF

echo "Updated env.example"

echo ""
echo "Successfully added MCPO $SERVER_NAME server!"
echo "============================================"
echo "Next steps:"
echo "   1. Add any required environment variables to your .env file"
echo "   2. Test locally: ./scripts/dev-start.sh"
echo "   3. Deploy to Cloud Run: ./scripts/deploy-cloudrun.sh"
echo ""
echo "🌐 Your new server will be available at:"
echo "   - Local: http://localhost:$SERVER_PORT/docs"
echo "   - In OpenWebUI: Automatically integrated"
echo ""
echo "🔧 To remove this server, run:"
echo "   ./scripts/remove-mcpo-server.sh $SERVER_NAME" 