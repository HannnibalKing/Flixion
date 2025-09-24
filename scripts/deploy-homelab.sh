#!/bin/bash
#
# Enterprise Homelab Deployment Script
# ====================================
# Automated deployment of complete infrastructure stack
# with proper error handling and validation.
#

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_FILE="/var/log/homelab-deploy.log"
DOCKER_COMPOSE_VERSION="2.21.0"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

info() {
    log "${BLUE}[INFO]${NC} $1"
}

success() {
    log "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    log "${YELLOW}[WARNING]${NC} $1"
}

error() {
    log "${RED}[ERROR]${NC} $1"
}

error_exit() {
    error "$1"
    exit 1
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error_exit "This script must be run as root"
    fi
}

# Check system requirements
check_requirements() {
    info "Checking system requirements..."
    
    # Check OS
    if ! grep -q "Ubuntu" /etc/os-release; then
        warning "This script is optimized for Ubuntu. Proceed with caution."
    fi
    
    # Check available space
    local available_space
    available_space=$(df / | awk 'NR==2 {print $4}')
    if [[ $available_space -lt 10485760 ]]; then  # 10GB in KB
        error_exit "Insufficient disk space. At least 10GB required."
    fi
    
    # Check internet connectivity
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        error_exit "No internet connectivity. Cannot download required packages."
    fi
    
    success "System requirements check passed"
}

# Install Docker and Docker Compose
install_docker() {
    info "Installing Docker and Docker Compose..."
    
    if command -v docker >/dev/null 2>&1; then
        info "Docker already installed"
    else
        # Install Docker
        apt-get update
        apt-get install -y ca-certificates curl gnupg lsb-release
        
        # Add Docker's official GPG key
        mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        
        # Set up repository
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        # Install Docker Engine
        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
        
        # Start and enable Docker
        systemctl start docker
        systemctl enable docker
        
        success "Docker installed successfully"
    fi
    
    # Install Docker Compose
    if ! command -v docker-compose >/dev/null 2>&1; then
        info "Installing Docker Compose..."
        curl -L "https://github.com/docker/compose/releases/download/v${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        success "Docker Compose installed successfully"
    else
        info "Docker Compose already installed"
    fi
}

# Install system dependencies
install_dependencies() {
    info "Installing system dependencies..."
    
    apt-get update
    apt-get install -y \
        curl \
        wget \
        git \
        htop \
        iotop \
        iftop \
        net-tools \
        ufw \
        fail2ban \
        borgbackup \
        python3 \
        python3-pip \
        nginx \
        certbot \
        python3-certbot-nginx
    
    success "Dependencies installed successfully"
}

# Setup firewall
setup_firewall() {
    info "Configuring firewall..."
    
    # Enable UFW
    ufw --force enable
    
    # Default policies
    ufw default deny incoming
    ufw default allow outgoing
    
    # SSH
    ufw allow ssh
    
    # HTTP and HTTPS
    ufw allow 80/tcp
    ufw allow 443/tcp
    
    # Media services
    ufw allow 8096/tcp  # Jellyfin
    ufw allow 5055/tcp  # Jellyseerr
    
    # Admin services (restrict to local network)
    ufw allow from 192.168.0.0/16 to any port 7878  # Radarr
    ufw allow from 192.168.0.0/16 to any port 8989  # Sonarr
    ufw allow from 192.168.0.0/16 to any port 9696  # Prowlarr
    
    success "Firewall configured successfully"
}

# Create directory structure
create_directories() {
    info "Creating directory structure..."
    
    local directories=(
        "/opt/homelab"
        "/opt/loa"
        "/opt/backups"
        "/mnt/docker/configs"
        "/mnt/storage/Movies"
        "/mnt/storage/TV"
        "/mnt/storage/Music"
        "/mnt/storage/Downloads"
        "/mnt/backups"
        "/var/log/homelab"
    )
    
    for dir in "${directories[@]}"; do
        mkdir -p "$dir"
        info "Created directory: $dir"
    done
    
    success "Directory structure created"
}

# Copy configuration files
copy_configs() {
    info "Copying configuration files..."
    
    # Copy Docker Compose files
    cp "$PROJECT_ROOT/docker-stacks/"* "/opt/homelab/"
    
    # Copy scripts
    cp "$PROJECT_ROOT/scripts/"* "/opt/backups/"
    chmod +x /opt/backups/*.sh
    
    # Copy LOA system
    cp -r "$PROJECT_ROOT/loa-offline-system/"* "/opt/loa/"
    chmod +x /opt/loa/*.sh
    
    # Copy systemd services
    cp "$PROJECT_ROOT/systemd-services/"* "/etc/systemd/system/"
    
    success "Configuration files copied"
}

# Setup systemd services
setup_services() {
    info "Setting up systemd services..."
    
    systemctl daemon-reload
    
    # Enable and start LOA controller
    systemctl enable loa-controller.service
    systemctl start loa-controller.service
    
    # Enable backup timer
    systemctl enable enterprise-backup.timer
    systemctl start enterprise-backup.timer
    
    success "Systemd services configured"
}

# Create Docker networks
create_networks() {
    info "Creating Docker networks..."
    
    local networks=(
        "homelab_default"
        "homelab_media_network"
    )
    
    for network in "${networks[@]}"; do
        if ! docker network ls | grep -q "$network"; then
            docker network create "$network"
            info "Created network: $network"
        else
            info "Network already exists: $network"
        fi
    done
    
    success "Docker networks created"
}

# Deploy services
deploy_services() {
    info "Deploying services..."
    
    cd /opt/homelab
    
    # Check if .env exists
    if [[ ! -f .env ]]; then
        warning ".env file not found. Creating from example..."
        cp .env.example .env
        warning "Please edit /opt/homelab/.env with your configuration before starting services"
        return 0
    fi
    
    # Deploy media stack
    info "Deploying media stack..."
    docker-compose -f docker-compose-media-stack.yml up -d
    
    # Deploy authentication stack
    info "Deploying authentication stack..."
    docker-compose -f docker-compose-authelia.yml up -d
    
    success "Services deployed successfully"
}

# Verify deployment
verify_deployment() {
    info "Verifying deployment..."
    
    # Check Docker services
    local failed_services=0
    
    info "Checking service health..."
    sleep 30  # Wait for services to start
    
    # List running containers
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    
    # Check specific services
    local services=("caddy" "jellyfin" "jellyseerr" "authelia")
    
    for service in "${services[@]}"; do
        if docker ps | grep -q "$service"; then
            success "$service is running"
        else
            error "$service is not running"
            ((failed_services++))
        fi
    done
    
    if [[ $failed_services -eq 0 ]]; then
        success "All core services are running"
    else
        warning "$failed_services services failed to start. Check logs with: docker-compose logs"
    fi
    
    # Check systemd services
    if systemctl is-active --quiet loa-controller; then
        success "LOA controller is active"
    else
        warning "LOA controller is not active"
    fi
}

# Print completion message
print_completion() {
    success "Homelab deployment completed!"
    
    echo
    echo "====================================================="
    echo "🎉 ENTERPRISE HOMELAB DEPLOYMENT COMPLETE"
    echo "====================================================="
    echo
    echo "📂 Configuration Files:"
    echo "   - Docker Compose: /opt/homelab/"
    echo "   - Scripts: /opt/backups/"
    echo "   - LOA System: /opt/loa/"
    echo
    echo "🔧 Next Steps:"
    echo "   1. Edit /opt/homelab/.env with your configuration"
    echo "   2. Configure DNS records for your domain"
    echo "   3. Update Authelia configuration"
    echo "   4. Start services: cd /opt/homelab && docker-compose up -d"
    echo
    echo "📋 Management Commands:"
    echo "   - View logs: docker-compose logs -f [service]"
    echo "   - Restart service: docker-compose restart [service]"
    echo "   - Update services: docker-compose pull && docker-compose up -d"
    echo
    echo "🔍 Monitoring:"
    echo "   - System logs: journalctl -f"
    echo "   - Backup status: systemctl status enterprise-backup.timer"
    echo "   - LOA status: systemctl status loa-controller"
    echo
    echo "====================================================="
}

# Main execution
main() {
    info "Starting Enterprise Homelab deployment..."
    
    check_root
    check_requirements
    install_dependencies
    install_docker
    setup_firewall
    create_directories
    copy_configs
    create_networks
    setup_services
    deploy_services
    verify_deployment
    print_completion
}

# Execute main function
main "$@"