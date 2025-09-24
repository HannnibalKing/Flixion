# Quick Start Guide

Get your enterprise homelab up and running in 30 minutes.

## Prerequisites

- Ubuntu 22.04 LTS server
- 16GB RAM minimum (32GB recommended)
- 500GB storage minimum (1TB+ recommended)
- Domain name with DNS control
- VPN provider account

## 1. Clone and Deploy

```bash
# Clone the repository
git clone https://github.com/yourusername/homelab-portfolio.git
cd homelab-portfolio

# Run automated deployment
sudo ./scripts/deploy-homelab.sh
```

## 2. Configure Environment

```bash
# Edit configuration file
sudo nano /opt/homelab/.env

# Required settings:
# - PUID/PGID (your user IDs)
# - TZ (your timezone)
# - Storage paths
# - VPN credentials
# - Domain names
```

## 3. Start Services

```bash
cd /opt/homelab

# Start media stack
docker-compose -f docker-compose-media-stack.yml up -d

# Start authentication
docker-compose -f docker-compose-authelia.yml up -d
```

## 4. Configure DNS

Point these subdomains to your server:
- `jellyfin.yourdomain.com`
- `requests.yourdomain.com`
- `auth.yourdomain.com`
- `admin.yourdomain.com`

## 5. Access Services

- **Media Server**: https://jellyfin.yourdomain.com
- **Request Management**: https://requests.yourdomain.com
- **Authentication**: https://auth.yourdomain.com
- **Admin Panel**: https://admin.yourdomain.com

## Troubleshooting

- **Services not starting**: Check `docker-compose logs [service]`
- **Authentication issues**: Verify Authelia configuration
- **DNS problems**: Confirm domain DNS records
- **VPN not connecting**: Check Gluetun logs and credentials

## Security Checklist

- [ ] Change default passwords
- [ ] Configure MFA in Authelia
- [ ] Update firewall rules for your network
- [ ] Set up backup encryption key
- [ ] Enable fail2ban monitoring

Need help? Check the [troubleshooting guide](./troubleshooting.md) or open an issue.