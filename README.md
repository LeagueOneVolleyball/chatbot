# OpenWebUI + MCPO Chatbot Infrastructure

Automated deployment and management scripts for running OpenWebUI with MCPO (Multiple MCP Server via MCPO) on Google Cloud Platform VMs.

## 🚀 Features

- **Automated OpenWebUI Updates**: Script to safely update OpenWebUI containers with backup and health checks
- **MCPO Integration**: Multiple MCP Server support including Snowflake, Time, Memory, and Sequential Thinking
- **GCP VM Deployment**: Complete infrastructure setup on Google Cloud Platform
- **Health Monitoring**: Robust health check system for service verification
- **Backup Management**: Automatic data backup before updates

## 📁 Project Structure

```
├── config/
│   └── mcpo-config.json          # MCPO server configuration
├── scripts/
│   ├── update-openwebui.sh       # ✨ Main update script (with fixed health checks)
│   ├── deploy-app-to-vm.sh       # Complete deployment to GCP VM
│   ├── deploy-gcp-vm.sh          # GCP VM creation
│   ├── upload-to-vm.sh           # Upload application files
│   └── start-snowflake-*.sh      # Snowflake MCP server scripts
├── docker-compose.yml            # Service orchestration
├── Dockerfile.mcpo               # MCPO container build
├── Dockerfile.openwebui          # Custom OpenWebUI container build
└── env.example                   # Environment template
```

## 🛠 Setup

### Prerequisites

- Google Cloud SDK (`gcloud`) installed and authenticated
- Docker and Docker Compose
- `.env` file with required environment variables (see `env.example`)

### Environment Variables

Create a `.env` file based on `env.example`:

```bash
# OpenAI Configuration
OPENAI_API_KEY=your_openai_api_key_here

# Snowflake Configuration  
SNOWFLAKE_ACCOUNT=your_account
SNOWFLAKE_USER=your_user
SNOWFLAKE_PRIVATE_KEY_PASSPHRASE=your_passphrase

# WebUI Configuration
WEBUI_SECRET_KEY=your_secret_key
MCPO_SNOWFLAKE_API_KEY=your_api_key
```

## 🚀 Quick Start

### 1. Deploy to GCP VM

```bash
# Complete deployment (creates VM, uploads code, starts services)
./scripts/deploy-app-to-vm.sh
```

### 2. Update OpenWebUI

```bash
# Update OpenWebUI to latest version
./scripts/update-openwebui.sh
```

## 🔧 Update Script Features

The `update-openwebui.sh` script includes:

- ✅ **Fixed Health Checks**: Properly detects service health status
- ✅ **Automatic Backup**: Creates timestamped backups before updates
- ✅ **Latest Image Pull**: Downloads newest OpenWebUI version
- ✅ **Service Orchestration**: Manages MCPO and OpenWebUI dependencies
- ✅ **Verification**: Tests service accessibility after update
- ✅ **Error Handling**: Comprehensive error logging and recovery

### Health Check Fix

The recent update fixed a critical issue in health check logic:

**Before (broken):**
```bash
jq -r '.[0].Health // "unknown"'  # Assumed array format
```

**After (fixed):**
```bash
jq -r '.Health // "unknown"'      # Correct single object parsing
```

This fix reduces update time from ~15 minutes to ~2-3 minutes by properly detecting when services are ready.

## 🌐 Access URLs

After deployment, access your services at:

- **OpenWebUI**: `http://YOUR_VM_IP:8080`
- **MCPO API**: `http://YOUR_VM_IP:8001/docs`

## 🔒 Security

- Environment files (`.env`) are excluded from git
- GitHub push protection prevents secret exposure
- Private keys are secured with proper container permissions
- API endpoints protected with authentication keys

## 🧪 Available MCP Servers

- **Snowflake MCP**: Database queries and operations
- **Time MCP**: Time and date utilities
- **Memory MCP**: Conversation memory management
- **Sequential Thinking MCP**: Advanced reasoning capabilities

## 📊 Monitoring

Use the included health check script:

```bash
# Check service health
gcloud compute ssh VM_NAME --zone=ZONE --command="cd /app && sudo docker-compose ps"
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes (ensure no secrets in commits)
4. Test the update script
5. Submit a pull request

## 📝 License

This project is part of the League One Volleyball chatbot infrastructure.

---

🎯 **Ready to deploy?** Run `./scripts/deploy-app-to-vm.sh` to get started!