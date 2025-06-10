#!/bin/bash

# Script para revertir configuración modo Bridge para Raspberry Pi
# Revierte todos los cambios realizados por el script de configuración bridge

set -e # Salir si hay errores

echo "==============================================="
echo " INICIANDO REVERSIÓN DE CONFIGURACIÓN BRIDGE"
echo "==============================================="

# Funciones comunes
source "$(dirname "${BASH_SOURCE[0]}")/common-functions.sh"
detect_interfaces # Esta función debe definir ETHERNET_IF y WIFI_IF

# Variables por defecto si no se detectaron interfaces
ETHERNET_IF="${ETHERNET_IF:-eth0}"
WIFI_IF="${WIFI_IF:-wlan0}"

echo "[x] Deteniendo servicios..."
systemctl stop hostapd 2>/dev/null || true
systemctl stop systemd-networkd 2>/dev/null || true
systemctl stop init-service.service 2>/dev/null || true

echo "[⏳] Deshabilitando servicios..."
systemctl disable hostapd 2>/dev/null || true
systemctl disable systemd-networkd 2>/dev/null || true
systemctl disable init-service.service 2>/dev/null || true

echo "[x] Eliminando servicio init-service..."
if [ -f "/etc/systemd/system/init-service.service" ]; then
  rm -f /etc/systemd/system/init-service.service
  systemctl daemon-reload
  echo "[i] Servicio init-service eliminado."
fi

echo "[x] Eliminando archivos de configuración de systemd-networkd..."
rm -f /etc/systemd/network/05-br0.netdev
rm -f /etc/systemd/network/10-${ETHERNET_IF}-br0.network
rm -f /etc/systemd/network/20-br0-dhcp.network

echo "[x] Eliminando configuración de hostapd..."
rm -f /etc/hostapd/hostapd.conf

# Restaurar configuración por defecto de hostapd
if [ -f /etc/default/hostapd ]; then
  sed -i 's|^DAEMON_CONF=.*|#DAEMON_CONF=""|' /etc/default/hostapd
fi

if [ -f /etc/conf.d/hostapd ]; then
  rm -f /etc/conf.d/hostapd
fi

echo "[x] Eliminando servicio init-service..."
# Eliminar servicio personalizado
rm -f /etc/systemd/system/init-service.service

echo "[x] Eliminando configuraciones de kernel y sysctl..."
# Eliminar configuraciones de módulos del kernel
rm -f /etc/modules-load.d/bridge.conf

# Eliminar configuraciones sysctl
rm -f /etc/sysctl.d/99-bridge-ip_forward.conf
rm -f /etc/sysctl.d/99-bridge-nf.conf

echo "[x] Limpiando reglas de iptables..."
# Limpiar todas las reglas de iptables
iptables -F 2>/dev/null || true
iptables -X 2>/dev/null || true
iptables -t nat -F 2>/dev/null || true
iptables -t nat -X 2>/dev/null || true
iptables -t mangle -F 2>/dev/null || true
iptables -t mangle -X 2>/dev/null || true
iptables -t raw -F 2>/dev/null || true
iptables -t raw -X 2>/dev/null || true

# Restaurar políticas por defecto
iptables -P INPUT ACCEPT 2>/dev/null || true
iptables -P FORWARD ACCEPT 2>/dev/null || true
iptables -P OUTPUT ACCEPT 2>/dev/null || true

# Eliminar reglas guardadas
rm -f /etc/iptables/rules.v4 2>/dev/null || true
rm -f /etc/iptables/rules.v6 2>/dev/null || true

echo "[x] Deshabilitando IP forwarding..."
# Deshabilitar IP forwarding
echo 0 >/proc/sys/net/ipv4/ip_forward 2>/dev/null || true

echo "[ ] Eliminando puente br0..."
# echo "[⏳] Eliminando puente br0..."
# # Eliminar puente br0 si existe
# if ip link show br0 &>/dev/null; then
#   # Bajar interfaces del puente
#   ip link set dev ${ETHERNET_IF} nomaster 2>/dev/null || true
#   ip link set dev ${WIFI_IF} nomaster 2>/dev/null || true

#   # Bajar y eliminar el puente
#   ip link set dev br0 down 2>/dev/null || true
#   ip link delete br0 type bridge 2>/dev/null || true
# fi

echo "[x] Restaurando configuración de red por defecto..."
# Habilitar dhcpcd si estaba deshabilitado
systemctl enable dhcpcd 2>/dev/null || true

# Recargar systemd
systemctl daemon-reload

echo "[ ] Desmodulando módulos del kernel..."
# Intentar descargar módulos (puede fallar si están en uso)
# modprobe -r br_netfilter 2>/dev/null || true
# modprobe -r bridge 2>/dev/null || true

echo "[ ] Reiniciando servicios de red..."
# Reiniciar servicios de red
# systemctl restart dhcpcd 2>/dev/null || true
# systemctl restart networking 2>/dev/null || true

echo "[⏳] Reiniciar interfaces de red"
ip link set dev ${ETHERNET_IF} down 2>/dev/null || true
ip link set dev ${WIFI_IF} down 2>/dev/null || true
# sleep 2
ip link set dev ${ETHERNET_IF} up 2>/dev/null || true
ip link set dev ${WIFI_IF} up 2>/dev/null || true

echo ""
echo "==============================================="
echo " REVERSIÓN DE CONFIGURACIÓN BRIDGE COMPLETADA!"
echo "==============================================="
echo "CAMBIOS REVERTIDOS:"
echo "✓ Servicios hostapd y systemd-networkd deshabilitados"
echo "✓ Archivos de configuración de red eliminados"
echo "✓ Configuración de hostapd eliminada"
echo "✓ Servicio personalizado init-service eliminado"
echo "✓ Módulos del kernel y configuraciones sysctl eliminados"
echo "✓ Reglas de iptables limpiadas"
echo "✓ IP forwarding deshabilitado"
echo "✓ Puente br0 eliminado"
echo "✓ dhcpcd rehabilitado"
echo "==============================================="

echo "[!] Recuerde reiniciar manualmente para aplicar todos los cambios."
echo ""
