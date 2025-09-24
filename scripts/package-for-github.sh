#!/bin/bash
#
# Package the complete homelab portfolio for GitHub upload
# Creates a clean, ready-to-share directory structure
#

PORTFOLIO_DIR="/home/hansolo/Complete-Homelab-Portfolio"

# Make scripts executable
find "$PORTFOLIO_DIR/scripts" -name "*.sh" -exec chmod +x {} \;
find "$PORTFOLIO_DIR/loa-offline-system" -name "*.sh" -exec chmod +x {} \;

# Create final package info
cat > "$PORTFOLIO_DIR/PACKAGE_INFO.txt" << 'EOF'
Enterprise Homelab Portfolio Package
===================================

This package contains a complete, sanitized homelab infrastructure
showcasing enterprise-grade DevOps and Systems Administration skills.

Directory Structure:
├── README.md                 # Comprehensive documentation
├── docker-stacks/           # Production Docker Compose files
├── configs/                 # Configuration examples
├── scripts/                 # Automation and deployment scripts
├── loa-offline-system/      # Emergency offline knowledge system
├── systemd-services/        # System service definitions
└── docs/                    # Additional documentation

Key Features:
- GPU-accelerated media streaming
- VPN-secured downloading with kill-switch
- Multi-factor authentication system
- Automated encrypted backups
- Emergency offline knowledge archive (600GB+)
- Production security hardening
- Infrastructure as Code approach

Ready for GitHub upload and professional presentation.
EOF

# Create GitHub workflow example
mkdir -p "$PORTFOLIO_DIR/.github/workflows"
cat > "$PORTFOLIO_DIR/.github/workflows/docker-compose-validation.yml" << 'EOF'
name: Docker Compose Validation

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  validate:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Validate Docker Compose files
      run: |
        cd docker-stacks
        docker-compose -f docker-compose-media-stack.yml config
        docker-compose -f docker-compose-authelia.yml config
    
    - name: Validate shell scripts
      run: |
        find . -name "*.sh" -exec shellcheck {} \;
EOF

echo "✅ Portfolio package ready for GitHub upload!"
echo "📂 Location: $PORTFOLIO_DIR"
echo "📋 Use: scp -r $PORTFOLIO_DIR user@mainpc:~/Desktop/"