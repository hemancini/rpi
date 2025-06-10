#!/bin/bash

# Este script verifica el estado de la red después de un reinicio
# y muestra información relevante como interfaces, rutas, servicios y conectividad.

# Funciones comunes
source "$(dirname "${BASH_SOURCE[0]}")/common-functions.sh"

# Instalar paquetes necesarios
install_packages "iw net-tools"

# Cargar variables globales
source /etc/global_var.conf || true

echo "=== Verificación de red post-reinicio ==="
echo "Fecha: $(date)"
echo ""
echo "Network mode: $RPI_NETWORK_MODE"
echo ""
echo "IP del dispositivo: $(hostname -I | awk '{print $1}')"
echo ""
echo "Interfaces de red:"
ip addr show
echo ""
echo "Tabla de rutas:"
ip route show
echo ""
echo "Estado de servicios:"
echo "--- dhcpcd ---"
systemctl status dhcpcd --no-pager -l
echo ""
echo "--- systemd-networkd ---"
systemctl status systemd-networkd --no-pager -l
echo ""
echo "--- hostapd ---"
systemctl status hostapd --no-pager -l
echo ""
echo "--- dnsmasq ---"
systemctl status dnsmasq --no-pager -l
echo ""
echo "--- init-service ---"
# systemctl status init-service --no-pager -l
journalctl -u init-service --no-pager
echo ""
echo "Conectividad a internet:"
if ping -c 3 8.8.8.8 >/dev/null 2>&1; then
  echo "✓ Conexión a internet OK"
else
  echo "✗ Sin conexión a internet"
fi
echo ""
echo "Clientes WiFi conectados:"
iw dev wlan0 station dump 2>/dev/null || echo "No hay clientes conectados o interfaz no disponible"
