# GCP VM Deployment Guide

Deploy OpenWebUI + MCPO to Google Cloud Platform using a VM instance.

## Quick Deploy

```bash
./scripts/deploy-app-to-vm.sh
```

This script handles everything:
- Creates VM (if needed)
- Uploads application files
- Prompts for configuration
- Starts services
- Provides access URLs

## Manual Steps

If you prefer step-by-step:

```bash
# 1. Create VM
./scripts/deploy-gcp-vm.sh

# 2. Upload files
./scripts/upload-to-vm.sh

# 3. Complete setup
./scripts/deploy-app-to-vm.sh
```

## Prerequisites

- gcloud CLI installed and authenticated
- Snowflake private key file (update path in docker-compose.yml)
- OpenAI API key
- GCP project permissions

## What You Get

- **VM**: `openwebui-mcpo` in `comp-tool-poc-lovb` project
- **OpenWebUI**: `http://EXTERNAL_IP:8080`
- **MCPO API**: `http://EXTERNAL_IP:8001/docs`
- **Auto-start**: Services start automatically on boot

## VM Configuration

- **Machine**: e2-standard-2 (2 vCPUs, 8GB RAM)
- **Storage**: 50GB SSD
- **OS**: Ubuntu 22.04 LTS
- **Zone**: us-central1-a
- **Ports**: 8080 (OpenWebUI), 8001 (MCPO), 22 (SSH)

## Management

### Access
```bash
# Connect via SSH
gcloud compute ssh openwebui-mcpo --zone=us-central1-a

# Get external IP
gcloud compute instances describe openwebui-mcpo --zone=us-central1-a --format='get(networkInterfaces[0].accessConfigs[0].natIP)'
```

### Service Control
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

### Cost Management
```bash
# Stop VM (saves ~$50/month)
gcloud compute instances stop openwebui-mcpo --zone=us-central1-a

# Start VM when needed
gcloud compute instances start openwebui-mcpo --zone=us-central1-a
```

## Troubleshooting

### VM Creation Issues
```bash
# Check quotas
gcloud compute project-info describe --project=comp-tool-poc-lovb
```

### Service Issues
```bash
# Connect and check
gcloud compute ssh openwebui-mcpo --zone=us-central1-a
cd /app
docker-compose ps
docker-compose logs
```

### Access Issues
```bash
# Check firewall
gcloud compute firewall-rules list --filter="name:openwebui-firewall"

# Verify VM IP
gcloud compute instances describe openwebui-mcpo --zone=us-central1-a --format='get(networkInterfaces[0].accessConfigs[0].natIP)'
```

## Updates

### Application Updates
```bash
# Re-upload code
./scripts/upload-to-vm.sh

# Restart services
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

## Verification

After deployment:
1. Visit `http://EXTERNAL_IP:8080` - OpenWebUI interface
2. Visit `http://EXTERNAL_IP:8001/docs` - MCPO API docs
3. Test Snowflake query in chat interface
4. Check service health: `docker-compose ps`

That's it! Simple VM deployment with everything configured. 