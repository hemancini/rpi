#!/bin/bash

# Script para revertir los cambios del script de NAT/hotspot WiFi
# Revierte configuraciones de red, iptables, servicios y archivos de configuración

# Funciones comunes
source "$(dirname "${BASH_SOURCE[0]}")/common-functions.sh"
detect_interfaces # Esta función debe definir ETHERNET_IF y WIFI_IF

# Variables por defecto si no se detectaron las interfaces
WIFI_IF="${WIFI_IF:-wlan0}"
ETHERNET_IF="${ETHERNET_IF:-eth0}"
STATIC_WIFI_IP="192.168.4.1/24"

echo "================================================"
echo "INICIANDO REVERSIÓN DE CONFIGURACIÓN NAT/HOTSPOT"
echo "================================================"

echo "[x] Deteniendo servicios relacionados..."
systemctl stop hostapd 2>/dev/null || true
systemctl stop dnsmasq 2>/dev/null || true
systemctl stop init-service 2>/dev/null || true

echo "[x] Deshabilitando servicios..."
systemctl disable hostapd 2>/dev/null || true
systemctl disable dnsmasq 2>/dev/null || true
systemctl disable init-service 2>/dev/null || true

echo "[x] Eliminando servicio init-service..."
if [ -f "/etc/systemd/system/init-service.service" ]; then
  rm -f /etc/systemd/system/init-service.service
  systemctl daemon-reload
  echo "[i] Servicio init-service eliminado."
fi

echo "[x] Limpiando reglas de iptables..."
# Limpiar todas las reglas de iptables
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X

# Restaurar políticas por defecto a ACCEPT
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

echo "[x] Guardando reglas de iptables limpias..."
if command -v netfilter-persistent &>/dev/null; then
  netfilter-persistent save
fi

echo "[x] Eliminando configuración de IP estática de dhcpcd.conf..."
if [ -f /etc/dhcpcd.conf ]; then
  # Crear backup
  cp /etc/dhcpcd.conf /etc/dhcpcd.conf.backup.$(date +%Y%m%d_%H%M%S)

  # Eliminar bloque de configuración NAT
  sed -i "/# Configuración para NAT AP ($WIFI_IF) por script - .*/,/nohook wpa_supplicant/d" /etc/dhcpcd.conf
  echo "[i] Configuración de IP estática eliminada de dhcpcd.conf"
fi

echo "[x] Eliminando configuración de hostapd..."
if [ -f /etc/hostapd/hostapd.conf ]; then
  mv /etc/hostapd/hostapd.conf /etc/hostapd/hostapd.conf.backup.$(date +%Y%m%d_%H%M%S)
  echo "[i] Configuración de hostapd respaldada y eliminada."
fi

# Limpiar configuración de DAEMON_CONF
if [ -f /etc/default/hostapd ]; then
  sed -i 's|^DAEMON_CONF="/etc/hostapd/hostapd.conf"|#DAEMON_CONF=""|' /etc/default/hostapd
fi

echo "[x] Eliminando configuración de dnsmasq..."
if [ -f /etc/dnsmasq.conf ]; then
  mv /etc/dnsmasq.conf /etc/dnsmasq.conf.backup.$(date +%Y%m%d_%H%M%S)
  # Restaurar configuración por defecto básica
  touch /etc/dnsmasq.conf
  echo "[i] Configuración de dnsmasq respaldada y limpiada."
fi

echo "[x] Eliminando configuración de IP forwarding..."
if [ -f "/etc/sysctl.d/99-nat-ip_forward.conf" ]; then
  rm -f /etc/sysctl.d/99-nat-ip_forward.conf
  echo "[i] Archivo de IP forwarding eliminado."
fi

echo "[x] Deshabilitar IP forwarding inmediatamente"
echo 0 >/proc/sys/net/ipv4/ip_forward

echo "[x] Limpiando configuración de red de la interfaz WiFi..."
# Eliminar IP estática de la interfaz WiFi
ip addr flush dev $WIFI_IF 2>/dev/null || true

echo "[ ] Reiniciando servicios de red..."
# systemctl restart dhcpcd || true

# Intentar restaurar wpa_supplicant si estaba configurado
if [ -f /etc/wpa_supplicant/wpa_supplicant.conf ]; then
  echo "[x] Reiniciando wpa_supplicant..."
  systemctl restart wpa_supplicant || true
fi

echo "[x] Verificando estado de servicios..."
echo "Estado de hostapd: $(systemctl is-active hostapd 2>/dev/null || echo 'inactivo')"
echo "Estado de dnsmasq: $(systemctl is-active dnsmasq 2>/dev/null || echo 'inactivo')"
echo "Estado de dhcpcd: $(systemctl is-active dhcpcd 2>/dev/null || echo 'inactivo')"

echo "[x] Verificando IP forwarding..."
if [ "$(cat /proc/sys/net/ipv4/ip_forward)" -eq 0 ]; then
  echo "[i] IP forwarding deshabilitado correctamente."
else
  echo "[!] Advertencia: IP forwarding aún está habilitado."
fi

echo "[x] Verificando reglas de iptables..."
IPTABLES_RULES=$(iptables -L -n | wc -l)
if [ "$IPTABLES_RULES" -le 10 ]; then
  echo "[i] Reglas de iptables limpiadas correctamente."
else
  echo "[!] Advertencia: Aún existen reglas de iptables. Ejecuta 'iptables -L' para verificar."
fi

echo ""
echo "--------------------------------------------------------------------"
echo "REVERSIÓN COMPLETADA"
echo "--------------------------------------------------------------------"
echo "✓ Servicios NAT/hotspot detenidos y deshabilitados"
echo "✓ Reglas de iptables limpiadas"
echo "✓ IP forwarding deshabilitado"
echo "✓ Configuraciones de red restauradas"
echo "✓ Archivos de configuración respaldados"
echo ""
echo "ARCHIVOS RESPALDADOS:"
echo "- /etc/dhcpcd.conf.backup.*"
echo "- /etc/hostapd/hostapd.conf.backup.*"
echo "- /etc/dnsmasq.conf.backup.*"
echo ""
echo "NOTAS:"
echo "- La interfaz $WIFI_IF debería volver a su configuración normal"
echo "- Si tenías wpa_supplicant configurado, debería restaurarse automáticamente"
echo "- No es necesario reiniciar el sistema"
echo "- Verifica la conectividad de red después de unos segundos"
echo "--------------------------------------------------------------------"

# Mostrar estado final de las interfaces
echo ""
echo "Estado actual de las interfaces de red:"
ip addr show $WIFI_IF 2>/dev/null | head -5 || echo "No se pudo mostrar $WIFI_IF"
ip addr show $ETHERNET_IF 2>/dev/null | head -5 || echo "No se pudo mostrar $ETHERNET_IF"
