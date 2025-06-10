# Troubleshooting Guide for HTTP 500 Errors

This guide provides steps to troubleshoot HTTP 500 errors when running a web server on Raspberry Pi OS Lite.

## Troubleshooting Steps

### 1. Check Nginx Error Logs

```bash
sudo tail -n 50 /var/log/nginx/error.log
```

### 2. Check PHP-FPM Error Logs

```bash
sudo tail -n 50 /var/log/php*-fpm.log
# or
sudo journalctl -u php*-fpm --no-pager
```

### 3. Check PHP-FPM Socket Existence and Permissions

```bash
ls -la /var/run/php/
```

### 4. Validate Nginx Configuration

```bash
sudo nginx -t
```

## Common Issues

- Incorrect PHP-FPM socket path in Nginx configuration
- File permission issues in web directory
- PHP code errors
- Missing PHP extensions
- SELinux/AppArmor blocking access

## Resolution Steps

1. Update the PHP-FPM socket path in Nginx configuration
2. Check and fix file permissions
3. Restart services after making changes:

```bash
sudo systemctl restart nginx
sudo systemctl restart php*-fpm
```
