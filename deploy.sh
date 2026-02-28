#!/bin/bash

# ╔══════════════════════════════════════════════════════════════════════╗
# ║           ADAPTUSGROUP.CA DEPLOYMENT PACKAGE                       ║
# ╚══════════════════════════════════════════════════════════════════════╝

set -e

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║           ADAPTUSGROUP.CA - DEPLOYMENT SCRIPT                      ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}[INFO]${NC} Starting deployment for adaptusgroup.ca"
echo ""

# ┌─────────────────────────────────────────────────────────────────────┐
# │ STEP 1: PREREQUISITES                                              │
# └─────────────────────────────────────────────────────────────────────┘
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 1: Checking Prerequisites"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

check_command() {
    if command -v $1 &> /dev/null; then
        echo -e "  ✓ $1: $(which $1)"
    else
        echo -e "  ✗ $1: NOT FOUND"
        MISSING=true
    fi
}

MISSING=false
check_command "node"
check_command "npm"
check_command "nginx"
check_command "systemctl"

if [ "$MISSING" = true ]; then
    echo ""
    echo -e "${YELLOW}[WARNING]${NC} Install missing dependencies first!"
    echo ""
    echo "For Ubuntu:"
    echo "  apt update"
    echo "  apt install nginx nodejs npm curl -y"
    echo ""
fi

# ┌─────────────────────────────────────────────────────────────────────┐
# │ STEP 2: CONFIGURE PORT                                              │
# └─────────────────────────────────────────────────────────────────────┘
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 2: Configuration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

read -p "Enter port for website (default: 48726): " PORT
PORT=${PORT:-48726}

read -p "Enter domain (default: adaptusgroup.ca): " DOMAIN
DOMAIN=${DOMAIN:-adaptusgroup.ca}

# ┌─────────────────────────────────────────────────────────────────────┐
# │ STEP 3: SETUP NGINX                                                 │
# └─────────────────────────────────────────────────────────────────────┘
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 3: Setting up Nginx"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Backup existing Nginx config if exists
if [ -f /etc/nginx/sites-available/$DOMAIN.conf ]; then
    cp /etc/nginx/sites-available/$DOMAIN.conf /etc/nginx/sites-available/$DOMAIN.conf.backup
    echo -e "${YELLOW}[INFO]${NC} Backed up existing Nginx config"
fi

cat > /etc/nginx/sites-available/$DOMAIN.conf << EOF
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;

    location / {
        proxy_pass http://localhost:$PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
}

server {
    listen 443 ssl;
    server_name $DOMAIN www.$DOMAIN;

    location / {
        proxy_pass http://localhost:$PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
}

server {
    if (\$host = www.$DOMAIN) {
        return 301 https://\$host\$request_uri;
    }
    if (\$host = $DOMAIN) {
        return 301 https://\$host\$request_uri;
    }
    server_name $DOMAIN www.$DOMAIN;
    listen 80;
    return 404;
}
EOF

ln -sf /etc/nginx/sites-available/$DOMAIN.conf /etc/nginx/sites-enabled/

if nginx -t 2>&1; then
    echo -e "${GREEN}[✓]${NC} Nginx configuration valid"
    nginx -s reload || systemctl restart nginx
else
    echo -e "${RED}[ERROR]${NC} Nginx configuration test failed"
    # Restore backup if exists
    if [ -f /etc/nginx/sites-available/$DOMAIN.conf.backup ]; then
        cp /etc/nginx/sites-available/$DOMAIN.conf.backup /etc/nginx/sites-available/$DOMAIN.conf
        echo -e "${YELLOW}[INFO]${NC} Restored previous Nginx config"
    fi
    exit 1
fi

# ┌─────────────────────────────────────────────────────────────────────┐
# │ STEP 4: START APPLICATION                                           │
# └─────────────────────────────────────────────────────────────────────┘
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 4: Starting Application"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Kill any existing process on the port
fuser -k $PORT/tcp 2>/dev/null || true

# Start the application
PORT=$PORT npm start > /root/adaptus-website.log 2>&1 &

sleep 3

if curl -s -o /dev/null -w "%{http_code}" http://localhost:$PORT | grep -q "200"; then
    echo -e "${GREEN}[✓]${NC} Application started on port $PORT"
else
    echo -e "${YELLOW}[WARNING]${NC} Checking application status..."
fi

# ┌─────────────────────────────────────────────────────────────────────┐
# │ STEP 5: SSL CERTIFICATE                                            │
# └─────────────────────────────────────────────────────────────────────┘
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 5: SSL Certificate (Optional)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

read -p "Get SSL certificate? (y/n): " GET_SSL
if [ "$GET_SSL" = "y" ]; then
    read -p "Enter email for SSL: " SSL_EMAIL
    if certbot --nginx -d $DOMAIN -d www.$DOMAIN \
        --non-interactive --agree-tos --email $SSL_EMAIL; then
        echo -e "${GREEN}[✓]${NC} SSL certificate installed"

        # Add automatic renewal to crontab
        (crontab -l 2>/dev/null || true; echo "0 3 * * * certbot renew --quiet") | crontab -
        echo -e "${GREEN}[✓]${NC} Auto-renewal scheduled (3 AM daily)"
    else
        echo -e "${YELLOW}[WARNING]${NC} SSL installation failed. You can run certbot manually later."
    fi
fi

# ┌─────────────────────────────────────────────────────────────────────┐
# │ STEP 6: CREATE SYSTEMD SERVICE                                     │
# └─────────────────────────────────────────────────────────────────────┘
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 6: Creating Systemd Service"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cat > /etc/systemd/system/adaptus-website.service << EOF
[Unit]
Description=AdaptusGroup Website
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$(pwd)
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=10
Environment=PORT=$PORT
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable adaptus-website
systemctl start adaptus-website

sleep 2

if systemctl is-active --quiet adaptus-website; then
    echo -e "${GREEN}[✓]${NC} Service enabled and started"
else
    echo -e "${RED}[ERROR]${NC} Service failed to start"
    journalctl -u adaptus-website -n 20
fi

# ┌─────────────────────────────────────────────────────────────────────┐
# │ COMPLETION                                                         │
# └─────────────────────────────────────────────────────────────────────┘
echo ""
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║                    DEPLOYMENT COMPLETE!                           ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "ACCESS INFORMATION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  🌐 Website:      http://$DOMAIN"
echo "  🔧 Port:        $PORT"
echo "  📝 Logs:       journalctl -u adaptus-website -f"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "COMMANDS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Restart:    systemctl restart adaptus-website"
echo "  Stop:       systemctl stop adaptus-website"
echo "  Status:     systemctl status adaptus-website"
echo "  View Logs:  journalctl -u adaptus-website -f"
echo ""
echo -e "${GREEN}[SUCCESS]${NC} AdaptusGroup.ca is now deployed!"
echo ""
