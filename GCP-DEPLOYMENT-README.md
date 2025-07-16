# GCP VM Deployment Guide
## OpenWebUI + MCPO on Google Cloud Platform

This guide walks you through deploying your working OpenWebUI + MCPO setup to Google Cloud Platform using a Virtual Machine.

## What You'll Get

- **VM Instance**: `openwebui-mcpo` in project `comp-tool-poc-lovb`
- **OpenWebUI**: Accessible at `http://EXTERNAL_IP:8080`
- **MCPO Snowflake API**: Available at `http://EXTERNAL_IP:8001/docs`
- **Auto-start**: Services automatically start when VM boots
- **Secure**: Private keys properly managed with correct permissions

## Quick Deployment

### One-Command Deployment
```bash
./scripts/deploy-app-to-vm.sh
```

This script will:
1. Create the GCP VM (if needed)
2. Upload all your application files
3. Prompt for configuration (OpenAI API key, etc.)
4. Upload your Snowflake private key
5. Start the services
6. Give you the access URLs

### Step-by-Step Deployment

If you prefer to run each step manually:

```bash
# 1. Create the VM
./scripts/deploy-gcp-vm.sh

# 2. Upload application files
./scripts/upload-to-vm.sh

# 3. Complete setup and start services
./scripts/deploy-app-to-vm.sh
```

## Prerequisites

### Local Requirements
- gcloud CLI installed and authenticated
- Your Snowflake private key at `/Users/kevin/dev/keys/comp_role_key.p8`
- OpenAI API key
- Project set to `comp-tool-poc-lovb`

### GCP Project Setup
The scripts will automatically:
- Enable required APIs (Compute Engine, Secret Manager, Logging)
- Create VPC network and firewall rules
- Set up VM with proper configuration

## VM Configuration

### Instance Details
- **Machine Type**: e2-standard-2 (2 vCPUs, 8GB RAM)
- **Disk**: 50GB SSD
- **OS**: Ubuntu 22.04 LTS
- **Zone**: us-central1-a
- **Network**: Custom VPC with firewall rules for ports 8080, 8001, 22

### Installed Software
- Docker & Docker Compose
- Node.js (for potential future MCP servers)
- Standard development tools (git, curl, htop, etc.)

## Access & Management

### Access URLs
After deployment, you'll get:
```
OpenWebUI: http://EXTERNAL_IP:8080
MCPO API: http://EXTERNAL_IP:8001/docs
```

### SSH Access
```bash
gcloud compute ssh openwebui-mcpo --zone=us-central1-a
```

### Service Management
```bash
# View logs
gcloud compute ssh openwebui-mcpo --zone=us-central1-a --command='cd /app && docker-compose logs -f'

# Restart services
gcloud compute ssh openwebui-mcpo --zone=us-central1-a --command='cd /app && docker-compose restart'

# Stop services
gcloud compute ssh openwebui-mcpo --zone=us-central1-a --command='cd /app && docker-compose down'

# Start services
gcloud compute ssh openwebui-mcpo --zone=us-central1-a --command='cd /app && docker-compose up -d'
```

## Security Features

### Network Security
- Firewall rules restrict access to only necessary ports
- VM uses private service account with minimal permissions

### Data Security
- Snowflake private key stored with 600 permissions
- Environment variables secured in protected .env file
- Docker containers run as non-root users

### Access Control
- SSH access controlled by Google Cloud IAM
- API endpoints can be secured with authentication if needed

## Troubleshooting

### Common Issues

#### VM Creation Fails
```bash
# Check quotas and permissions
gcloud compute project-info describe --project=comp-tool-poc-lovb
```

#### Services Won't Start
```bash
# Connect to VM and check logs
gcloud compute ssh openwebui-mcpo --zone=us-central1-a
cd /app
docker-compose logs
```

#### Can't Access Web Interface
```bash
# Check firewall rules
gcloud compute firewall-rules list --filter="name:openwebui-firewall"

# Verify VM external IP
gcloud compute instances describe openwebui-mcpo --zone=us-central1-a --format='get(networkInterfaces[0].accessConfigs[0].natIP)'
```

### Service Status Check
```bash
# On the VM
cd /app
docker-compose ps
docker-compose logs mcpo-tools
docker-compose logs openwebui
```

## Cost Management

### VM Costs
- **e2-standard-2**: ~$50-60/month if running 24/7
- **Storage**: ~$2.50/month for 50GB

### Cost Optimization
```bash
# Stop VM when not in use
gcloud compute instances stop openwebui-mcpo --zone=us-central1-a

# Start VM when needed
gcloud compute instances start openwebui-mcpo --zone=us-central1-a
```

## Updates & Maintenance

### Updating Application Code
```bash
# Re-run upload script with new code
./scripts/upload-to-vm.sh

# Restart services to pick up changes
gcloud compute ssh openwebui-mcpo --zone=us-central1-a --command='cd /app && docker-compose restart'
```

### System Updates
```bash
# Connect to VM
gcloud compute ssh openwebui-mcpo --zone=us-central1-a

# Update system
sudo apt update && sudo apt upgrade -y

# Update Docker images
cd /app
docker-compose pull
docker-compose up -d
```

## Monitoring

### Health Checks
The deployment includes built-in health monitoring:
- Docker health checks for both services
- Automatic restart on failure
- Startup dependency management

### Logs
```bash
# Application logs
gcloud compute ssh openwebui-mcpo --zone=us-central1-a --command='cd /app && docker-compose logs -f'

# System logs
gcloud compute ssh openwebui-mcpo --zone=us-central1-a --command='sudo journalctl -u docker -f'
```

## Success Verification

After deployment, verify everything works:

1. **OpenWebUI**: Visit `http://EXTERNAL_IP:8080` - should show the chat interface
2. **MCPO API**: Visit `http://EXTERNAL_IP:8001/docs` - should show Swagger documentation
3. **Snowflake Connection**: Test a query in the OpenWebUI chat
4. **Service Health**: Check that both containers are healthy

## Support

### Getting Help
- Check logs first: `docker-compose logs`
- Verify environment: `cat /app/.env`
- Test individual services: `docker-compose ps`

### Script Locations
- VM Creation: `./scripts/deploy-gcp-vm.sh`
- File Upload: `./scripts/upload-to-vm.sh`
- Complete Setup: `./scripts/deploy-app-to-vm.sh`

---

**Ready to deploy?** Run `./scripts/deploy-app-to-vm.sh` to get started! 