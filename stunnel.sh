#!/bin/bash

# Stunnel Server Auto Installer
# Usage: sudo bash stunnel-server-installer.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log function
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root (use sudo)"
fi

log "Starting Stunnel Server Installation..."

# Detect OS
if [ -f /etc/debian_version ]; then
    OS="debian"
    log "Detected Debian/Ubuntu system"
elif [ -f /etc/redhat-release ]; then
    OS="redhat"
    log "Detected RedHat/CentOS system"
else
    error "Unsupported operating system"
fi

# Update system and install stunnel
log "Updating system packages..."
if [ "$OS" = "debian" ]; then
    apt update -y
    apt install -y stunnel4 openssl ufw
    STUNNEL_CONFIG="/etc/stunnel/stunnel.conf"
    STUNNEL_DEFAULT="/etc/default/stunnel4"
    STUNNEL_SERVICE="stunnel4"
elif [ "$OS" = "redhat" ]; then
    yum update -y
    yum install -y stunnel openssl firewalld
    STUNNEL_CONFIG="/etc/stunnel/stunnel.conf"
    STUNNEL_SERVICE="stunnel"
fi

log "Stunnel installed successfully"

# Create stunnel directory if not exists
mkdir -p /etc/stunnel

# Generate SSL certificate
log "Generating SSL certificate..."
openssl req -new -x509 -days 365 -nodes \
    -out /etc/stunnel/server.pem \
    -keyout /etc/stunnel/server.key \
    -subj "/C=US/ST=State/L=City/O=Organization/CN=stunnel-server" 2>/dev/null

# Set proper permissions
chmod 600 /etc/stunnel/server.key
chmod 644 /etc/stunnel/server.pem
chown root:root /etc/stunnel/server.*

log "SSL certificate generated"

# Create stunnel configuration
log "Creating stunnel configuration..."
cat > $STUNNEL_CONFIG << 'EOF'
# Stunnel Server Configuration
cert = /etc/stunnel/server.pem
key = /etc/stunnel/server.key
pid = /var/run/stunnel/stunnel.pid

# Logging
debug = 4
output = /var/log/stunnel.log

# Security settings
fips = no
setuid = stunnel4
setgid = stunnel4

# Service configuration
[vpn-server]
accept = 443
connect = 127.0.0.1:1080

# Optional: Add more services
# [ssh-tunnel]
# accept = 2222
# connect = 127.0.0.1:22
EOF

log "Configuration file created"

# Create PID directory
mkdir -p /var/run/stunnel
if [ "$OS" = "debian" ]; then
    chown stunnel4:stunnel4 /var/run/stunnel
fi

# Enable stunnel service
if [ "$OS" = "debian" ]; then
    log "Enabling stunnel service..."
    sed -i 's/ENABLED=0/ENABLED=1/' $STUNNEL_DEFAULT 2>/dev/null || echo "ENABLED=1" > $STUNNEL_DEFAULT
fi

# Configure firewall
log "Configuring firewall..."
if [ "$OS" = "debian" ]; then
    # UFW configuration
    ufw --force enable
    ufw allow 443/tcp
    ufw allow ssh
    log "UFW firewall configured"
elif [ "$OS" = "redhat" ]; then
    # Firewalld configuration
    systemctl enable firewalld
    systemctl start firewalld
    firewall-cmd --permanent --add-port=443/tcp
    firewall-cmd --permanent --add-service=ssh
    firewall-cmd --reload
    log "Firewalld configured"
fi

# Start and enable stunnel service
log "Starting stunnel service..."
systemctl daemon-reload
systemctl enable $STUNNEL_SERVICE
systemctl restart $STUNNEL_SERVICE

# Wait a moment for service to start
sleep 2

# Check service status
if systemctl is-active --quiet $STUNNEL_SERVICE; then
    log "Stunnel service started successfully"
else
    error "Failed to start stunnel service"
fi

# Display configuration summary
echo ""
echo -e "${BLUE}================================================${NC}"
echo -e "${GREEN}    Stunnel Server Installation Complete!${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""
echo -e "${YELLOW}Server Configuration:${NC}"
echo "• Listening on: 0.0.0.0:443 (SSL/TLS)"
echo "• Forwarding to: 127.0.0.1:1080"
echo "• SSL Certificate: /etc/stunnel/server.pem"
echo "• Configuration: $STUNNEL_CONFIG"
echo "• Log file: /var/log/stunnel.log"
echo ""
echo -e "${YELLOW}Service Management:${NC}"
echo "• Status: systemctl status $STUNNEL_SERVICE"
echo "• Stop: systemctl stop $STUNNEL_SERVICE"
echo "• Start: systemctl start $STUNNEL_SERVICE"
echo "• Restart: systemctl restart $STUNNEL_SERVICE"
echo ""
echo -e "${YELLOW}Client Configuration Example:${NC}"
echo "client = yes"
echo "[vpn]"
echo "accept = 127.0.0.1:1080"
echo "connect = $(curl -s ifconfig.me 2>/dev/null || echo "YOUR_SERVER_IP"):443"
echo ""

# Check if service is listening
if netstat -tlnp 2>/dev/null | grep -q ":443.*stunnel" || ss -tlnp 2>/dev/null | grep -q ":443.*stunnel"; then
    echo -e "${GREEN}✓ Stunnel is listening on port 443${NC}"
else
    warning "Stunnel might not be listening on port 443. Check logs:"
    echo "  tail -f /var/log/stunnel.log"
fi

echo ""
echo -e "${GREEN}Installation completed successfully!${NC}"
echo -e "${YELLOW}Note: Make sure your target service is running on 127.0.0.1:1080${NC}"
