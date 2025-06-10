#!/bin/bash

# Exit on any error
set -e

# Funciones comunes
source "$(dirname "${BASH_SOURCE[0]}")/../common-functions.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root or with sudo."
    exit 1
fi

install_packages "php-cli php-fpm nginx sudo git"

# Create directory structure
print_message "Creating directory structure..."
mkdir -p /var/www/bashrunner || {
    print_error "Failed to create directory structure."
    exit 1
}

# Copy application files
print_message "Copying application files..."
if [ -f "index.php" ] && [ -f "style.css" ] && [ -f "scripts.js" ]; then
    cp index.php /var/www/bashrunner/ || {
        print_error "Failed to copy index.php to destination."
        exit 1
    }
    cp style.css /var/www/bashrunner/ || {
        print_error "Failed to copy style.css to destination."
        exit 1
    }
    cp scripts.js /var/www/bashrunner/ || {
        print_error "Failed to copy scripts.js to destination."
        exit 1
    }
    cp ps4.html /var/www/bashrunner/ || {
        print_error "Failed to copy ps4.html to destination."
        exit 1
    }
else
    print_error "Application files not found in current directory. Make sure index.php, style.css, and scripts.js exist."
    exit 1
fi

# Configure sudo for www-data (nginx user)
print_message "Configuring sudo permissions..."
# Create a new sudoers file for www-data
cat >/etc/sudoers.d/www-data-bash <<EOF
# Allow www-data to run specific commands without password
www-data ALL=(ALL) NOPASSWD: /bin/bash, /usr/bin/tail, /bin/chmod, /bin/ls, /usr/bin/find
EOF

chmod 0440 /etc/sudoers.d/www-data-bash || {
    print_error "Failed to set permissions on sudoers file."
    exit 1
}

# Configure Nginx
print_message "Configuring Nginx..."
cat >/etc/nginx/sites-available/bashrunner.conf <<EOF
server {
    listen 80;
    server_name localhost;
    root /var/www/bashrunner;
    index index.php;

    location / {
        if (\$http_user_agent ~* "PlayStation 4|PS4") {
            rewrite ^.*\$ /ps4.html last;
        }
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php-fpm.sock;
        fastcgi_read_timeout 300;
        fastcgi_send_timeout 300;
    }

    location ~ \.html\$ {
        try_files \$uri =404;
    }

    client_max_body_size 50M;
}
EOF

ln -sf /etc/nginx/sites-available/bashrunner.conf /etc/nginx/sites-enabled/ || {
    print_error "Failed to enable Nginx site configuration."
    exit 1
}

# Remove default site if it exists
if [ -f /etc/nginx/sites-enabled/default ]; then
    rm -f /etc/nginx/sites-enabled/default
fi

# Create logs directory
print_message "Creating logs directory..."
mkdir -p /var/log/bashrunner || {
    print_error "Failed to create logs directory."
    exit 1
}
chmod 777 /var/log/bashrunner || {
    print_error "Failed to set permissions on logs directory."
    exit 1
}

# Set permissions for www-data
print_message "Setting permissions for www-data..."
chown -R www-data:www-data /var/www/bashrunner || {
    print_error "Failed to set ownership on web directory."
    exit 1
}
chmod 755 /var/www/bashrunner || {
    print_error "Failed to set permissions on web directory."
    exit 1
}

# Check PHP-FPM configuration and get the service name
PHP_FPM_SERVICE=""
for service in php7.4-fpm php7.3-fpm php7.2-fpm php7.0-fpm php5.6-fpm php8.0-fpm php8.1-fpm php8.2-fpm php-fpm; do
    if systemctl list-units --full -all | grep -Fq "$service"; then
        PHP_FPM_SERVICE="$service"
        break
    fi
done

if [ -z "$PHP_FPM_SERVICE" ]; then
    print_warning "Could not determine PHP-FPM service name. You may need to restart it manually."
else
    print_message "Found PHP-FPM service: $PHP_FPM_SERVICE"
fi

# Restart services
print_message "Restarting services..."
systemctl restart nginx || {
    print_error "Failed to restart Nginx. Please check the service status."
}

if [ -n "$PHP_FPM_SERVICE" ]; then
    systemctl restart "$PHP_FPM_SERVICE" || {
        print_error "Failed to restart PHP-FPM. Please check the service status."
    }
fi

# Get server IP address
SERVER_IP=$(hostname -I | awk '{print $1}')

print_message "Setup completed successfully!"
print_message "Access the application at http://$SERVER_IP"
print_message "Current date and time: $(date +'%Y-%m-%d %H:%M:%S')"

# Information about the user that will be running the web application
WEB_USER=$(grep -r "^user" /etc/nginx/nginx.conf | awk '{print $2}' | tr -d ';')
if [ -z "$WEB_USER" ]; then
    WEB_USER="www-data"
fi
print_message "Web server running as user: $WEB_USER"

# Show current PHP version
PHP_VERSION=$(php -v | head -n 1)
print_message "PHP version: $PHP_VERSION"

# Current date and time
CURRENT_DATE=$(date '+%Y-%m-%d %H:%M:%S')
CURRENT_USER=$(whoami)

echo -e "\n${GREEN}# Troubleshooting Guide for HTTP 500 Errors${NC}"
echo -e "Current Date and Time (UTC): ${BLUE}${CURRENT_DATE}${NC}"
echo -e "Current User's Login: ${BLUE}${CURRENT_USER}${NC}"
echo ""

echo -e "${YELLOW}## Troubleshooting Steps${NC}"
echo ""

echo -e "${GREEN}### 1. Check Nginx Error Logs${NC}"
echo -e "${BLUE}sudo tail -n 50 /var/log/nginx/error.log${NC}"
echo ""

echo -e "${GREEN}### 2. Check PHP-FPM Error Logs${NC}"
echo -e "${BLUE}sudo tail -n 50 /var/log/php*-fpm.log${NC}"
echo -e "${BLUE}sudo journalctl -u php*-fpm --no-pager${NC}"
echo ""

echo -e "${GREEN}### 3. Check PHP-FPM Socket Existence and Permissions${NC}"
echo -e "${BLUE}ls -la /var/run/php/${NC}"
echo ""

echo -e "${GREEN}### 4. Validate Nginx Configuration${NC}"
echo -e "${BLUE}sudo nginx -t${NC}"
echo ""

echo -e "${YELLOW}## Common Issues${NC}"
echo -e "- Incorrect PHP-FPM socket path in Nginx configuration"
echo -e "- File permission issues in web directory"
echo -e "- PHP code errors"
echo -e "- Missing PHP extensions"
echo -e "- SELinux/AppArmor blocking access"
echo ""

echo -e "${YELLOW}## Resolution Steps${NC}"
echo -e "1. Update the PHP-FPM socket path in Nginx configuration"
echo -e "2. Check and fix file permissions"
echo -e "3. Restart services after making changes:"
echo -e "${BLUE}sudo systemctl restart nginx${NC}"
echo -e "${BLUE}sudo systemctl restart php*-fpm${NC}"
