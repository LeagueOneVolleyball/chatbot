# OpenWebUI + MCPO: Modern MCP Integration

This project provides a complete setup for running **OpenWebUI** with **MCPO (MCP-to-OpenAPI proxy)** integration, supporting both local development and Google Cloud Run deployment.

## 🎯 What This Gives You

- **OpenWebUI** with modern chat interface
- **MCPO servers** that convert MCP tools to REST APIs
- **Snowflake integration** out of the box
- **Extensible architecture** for adding new MCP servers
- **Local development** and **Cloud Run deployment**
- **Automatic service discovery** and health monitoring

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   OpenWebUI     │    │  MCPO Snowflake │    │  MCPO GitHub    │
│   Port 8080     │◄──►│   Port 8001     │    │   Port 8002     │
│                 │    │                 │    │                 │
│ - Chat Interface│    │ - SQL Queries   │    │ - Repo Access   │
│ - API Discovery │    │ - Data Analysis │    │ - Issue Tracking│
│ - Tool Calling  │    │ - Reporting     │    │ - Code Search   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## 🚀 Quick Start

### Prerequisites

1. **Docker & Docker Compose** installed
2. **Snowflake account** with service account and private key
3. **OpenAI API key** (or compatible API)
4. **Google Cloud SDK** (for Cloud Run deployment)

### Local Development

1. **Clone and setup**:
   ```bash
   git clone <your-repo>
   cd comptool-openwebui
   cp env.example .env
   # Edit .env with your configuration
   ```

2. **Start development environment**:
   ```bash
   ./scripts/dev-start.sh
   ```

3. **Access services**:
   - OpenWebUI: http://localhost:8080
   - MCPO Snowflake API: http://localhost:8001/docs

### Cloud Run Deployment

1. **Set up Google Cloud**:
   ```bash
   export PROJECT_ID=your-project-id
   gcloud auth login
   gcloud config set project $PROJECT_ID
   ```

2. **Deploy**:
   ```bash
   ./scripts/deploy-cloudrun.sh
   ```

## 📋 Configuration

### Environment Variables

```bash
# OpenAI Configuration
OPENAI_API_KEY=your-openai-api-key
OPENAI_API_BASE_URL=https://api.openai.com/v1

# WebUI Configuration
WEBUI_AUTH=false
WEBUI_SECRET_KEY=your-secret-key-here

# Snowflake Configuration
SNOWFLAKE_ACCOUNT=your-account-id
SNOWFLAKE_USER=your-service-account
SNOWFLAKE_WAREHOUSE=your-warehouse
SNOWFLAKE_DATABASE=your-database
SNOWFLAKE_SCHEMA=PUBLIC
SNOWFLAKE_ROLE=your-role
SNOWFLAKE_PRIVATE_KEY_PASSPHRASE=your-passphrase
```

### Snowflake Setup

1. **Private Key Location**: `/Users/kevin/dev/keys/comp_role_key.p8`
2. **Service Account**: Must have appropriate permissions
3. **Warehouse**: Should be auto-suspend enabled for cost optimization

## 🔧 Adding New MCPO Servers

The system is designed to be easily extensible. Add new MCP servers with one command:

```bash
# Add GitHub integration
./scripts/add-mcpo-server.sh github 8002 "uvx mcp-server-github"

# Add filesystem access
./scripts/add-mcpo-server.sh filesystem 8003 "uvx mcp-server-filesystem"

# Add PostgreSQL integration
./scripts/add-mcpo-server.sh postgres 8004 "uvx mcp-server-postgres"
```

### Available MCP Servers

- **mcp-server-github**: GitHub repository integration
- **mcp-server-filesystem**: File system access
- **mcp-server-postgres**: PostgreSQL database
- **mcp-server-sqlite**: SQLite database
- **mcp-server-fetch**: HTTP requests
- **mcp-server-brave-search**: Web search

## 🌐 Deployment Options

### Local Development (Docker Compose)

- **File**: `docker-compose.mcpo.yml`
- **Command**: `./scripts/dev-start.sh`
- **Benefits**: Fast iteration, easy debugging

### Google Cloud Run

- **File**: `Dockerfile.cloudrun`
- **Command**: `./scripts/deploy-cloudrun.sh`
- **Benefits**: Serverless, auto-scaling, managed

## 🔍 Monitoring & Debugging

### Health Checks

All services include health checks:

```bash
# Check MCPO Snowflake
curl http://localhost:8001/docs

# Check OpenWebUI
curl http://localhost:8080

# Run full health check
python scripts/health-check-cloudrun.py
```

### Logs

```bash
# Local development
docker-compose -f docker-compose.mcpo.yml logs -f

# Cloud Run
gcloud run services logs read openwebui-mcpo --region=us-central1
```

### Testing Snowflake Connection

```bash
# Test database listing
curl -X POST http://localhost:8001/list_databases \
  -H "Content-Type: application/json" \
  -d '{}'

# Test SQL query
curl -X POST http://localhost:8001/execute_query \
  -H "Content-Type: application/json" \
  -d '{"query": "SELECT CURRENT_TIMESTAMP() as current_time"}'
```

## 🛠️ Development

### Project Structure

```
comptool-openwebui/
├── config/
│   └── mcpo-config.json            # MCPO configuration
├── scripts/
│   ├── dev-start.sh                # Local development
│   ├── add-mcpo-server.sh          # Add new MCPO servers
│   ├── start-snowflake-local.sh    # Local Snowflake development
│   ├── start-snowflake-production.sh # Production Snowflake startup
│   └── validate-setup.sh           # Setup validation
├── logs/                           # Application logs
├── docker-compose.yml              # Local development
├── Dockerfile.mcpo                 # MCPO server image
└── env.example                     # Environment template
```

### Key Features

1. **Service Discovery**: OpenWebUI automatically discovers available MCPO servers
2. **Health Monitoring**: Comprehensive health checks for all services
3. **Extensible**: Easy to add new MCP servers
4. **Cloud Ready**: Optimized for Google Cloud Run deployment
5. **Development Friendly**: Fast local development with hot reloading

## 🚨 Troubleshooting

### Common Issues

1. **Snowflake Connection Failed**:
   - Check account identifier format (should be `ACCOUNT-ID`, not `ACCOUNT-ID.snowflakecomputing.com`)
   - Verify private key path and permissions
   - Ensure service account has proper role assignments

2. **MCPO Server Not Starting**:
   - Check if the MCP server package is installed
   - Verify environment variables are set correctly
   - Look at container logs for specific error messages

3. **OpenWebUI Can't Connect to MCPO**:
   - Ensure MCPO servers are healthy before OpenWebUI starts
   - Check network connectivity between containers
   - Verify port mappings in docker-compose.yml

### Debug Commands

```bash
# Check service status
docker-compose -f docker-compose.mcpo.yml ps

# View specific service logs
docker-compose -f docker-compose.mcpo.yml logs mcpo-snowflake

# Test MCPO server directly
curl -X POST http://localhost:8001/list_databases -H "Content-Type: application/json" -d '{}'

# Check OpenWebUI configuration
docker-compose -f docker-compose.mcpo.yml exec openwebui python -c "from config import mcpo_config; print(mcpo_config.mcpo_servers)"
```

## 🧪 Testing and Development

### Local Development
```bash
# Start local development environment
./scripts/dev-start.sh

# Start just Snowflake MCPO locally
./scripts/start-snowflake-local.sh

# Validate your setup
./scripts/validate-setup.sh
```

## 🎉 Success Metrics

After setup, you should have:

- ✅ OpenWebUI running and accessible
- ✅ MCPO Snowflake server responding to API calls
- ✅ Automatic service discovery working
- ✅ Health checks passing
- ✅ Logs showing successful connections

## 🔗 Useful Links

- [OpenWebUI Documentation](https://docs.openwebui.com/)
- [MCPO GitHub Repository](https://github.com/modelcontextprotocol/mcpo)
- [MCP Server Registry](https://github.com/modelcontextprotocol/servers)
- [Google Cloud Run Documentation](https://cloud.google.com/run/docs)

---

**Need help?** Check the logs, review the health checks, and ensure all environment variables are properly configured. 