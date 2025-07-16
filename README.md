# OpenWebUI + MCPO

A complete setup for running **OpenWebUI** with **MCPO (MCP-to-OpenAPI proxy)** integration, supporting local development and Google Cloud VM deployment.

## Quick Start

### Prerequisites
- Docker & Docker Compose
- OpenAI API key
- Snowflake account with service account and private key
- Google Cloud SDK (for VM deployment)

### Local Development
```bash
# 1. Configure environment
cp env.example .env
# Edit .env with your values

# 2. Start services
docker-compose up -d

# 3. Access
# OpenWebUI: http://localhost:8080
# MCPO API: http://localhost:8001/docs
```

### GCP VM Deployment
```bash
# Complete deployment (creates VM, uploads files, starts services)
./scripts/deploy-app-to-vm.sh
```

## What You Get

- **OpenWebUI**: Modern chat interface with tool calling
- **MCPO Snowflake Server**: Converts Snowflake MCP tools to REST API
- **Automatic Integration**: OpenWebUI discovers and uses MCPO tools
- **Health Monitoring**: Built-in health checks and auto-restart

## Architecture

```
OpenWebUI (8080) ←→ MCPO Snowflake Server (8001) ←→ Snowflake Database
```

## Configuration

### Required Environment Variables
```bash
# OpenAI
OPENAI_API_KEY=your-openai-api-key

# Snowflake
SNOWFLAKE_ACCOUNT=your-account-id
SNOWFLAKE_USER=your-service-account
SNOWFLAKE_PRIVATE_KEY_PASSPHRASE=your-passphrase
SNOWFLAKE_WAREHOUSE=your-warehouse
SNOWFLAKE_DATABASE=your-database
SNOWFLAKE_ROLE=your-role

# MCPO
MCPO_SNOWFLAKE_API_KEY=snowflake-secure-key-2024
```

**Note**: Update the Snowflake private key path in `docker-compose.yml` to match your key location.

See `env.example` for all available options.

## Scripts

- **`./scripts/validate-setup.sh`** - Validate configuration and dependencies
- **`./scripts/deploy-gcp-vm.sh`** - Create GCP VM instance
- **`./scripts/upload-to-vm.sh`** - Upload files to VM
- **`./scripts/deploy-app-to-vm.sh`** - Complete VM deployment
- **`./scripts/dev-start.sh`** - Start local development environment

## Project Structure

```
comptool-openwebui/
├── docker-compose.yml          # Service definitions
├── Dockerfile.openwebui        # OpenWebUI container
├── Dockerfile.mcpo            # MCPO server container
├── env.example               # Environment template
├── scripts/                  # Deployment and utility scripts
├── config/                   # Configuration files
└── logs/                     # Application logs
```

## Troubleshooting

### Validation
```bash
./scripts/validate-setup.sh --fix
```

### Common Issues
1. **Snowflake connection fails**: Check account format (use `ACCOUNT-ID`, not `ACCOUNT-ID.snowflakecomputing.com`)
2. **Services won't start**: Run validation script and check logs
3. **Can't access UI**: Verify ports 8080/8001 are available

### Logs
```bash
# Local
docker-compose logs -f

# VM
gcloud compute ssh openwebui-mcpo --zone=us-central1-a --command='cd /app && docker-compose logs -f'
```

## VM Management

```bash
# Connect to VM
gcloud compute ssh openwebui-mcpo --zone=us-central1-a

# Restart services
gcloud compute ssh openwebui-mcpo --zone=us-central1-a --command='cd /app && docker-compose restart'

# Stop VM (to save costs)
gcloud compute instances stop openwebui-mcpo --zone=us-central1-a

# Start VM
gcloud compute instances start openwebui-mcpo --zone=us-central1-a
```

That's it! The system is designed to be simple and just work. 