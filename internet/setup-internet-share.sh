#!/bin/bash

# Script principal para compartir internet de Ethernet a Wi-Fi en Raspberry Pi
# Selector de modo Bridge o NAT

# RPI_NETWORK_MODE
source /etc/global_var.conf
echo "Network mode: $RPI_NETWORK_MODE"

# Mostrar menú de selección
echo "==============================================="
echo " CONFIGURADOR DE COMPARTICIÓN DE INTERNET RPi"
echo "==============================================="
echo "Seleccione el modo de operación:"
echo "1) Modo Bridge (misma subred)"
echo "   - Todos los dispositivos en la misma red"
echo "   - Router principal asigna IPs"
echo "   - Necesita IP estática en el Pi"
echo "   - SIN bloqueo de dominios"
echo ""
echo "2) Modo NAT (subred independiente)"
echo "   - Crea nueva red Wi-Fi (192.168.4.0/24)"
echo "   - El Pi asigna IPs y gestiona DNS"
echo "   - CON bloqueo de dominios específicos"
echo "==============================================="

read -p "Ingrese su elección [1-2]: " mode_choice

# Validar selección
if [[ ! "$mode_choice" =~ ^[12]$ ]]; then
    echo "Opción inválida. Saliendo."
    exit 1
fi
# Obtener directorio del script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ejecutar script correspondiente
case $mode_choice in
1)
    echo "Ejecutando configuración en modo Bridge..."
    bash "$SCRIPT_DIR/setup-bridge-mode.sh"
    ;;
2)
    echo "Ejecutando configuración en modo NAT..."
    bash "$SCRIPT_DIR/setup-nat-mode.sh"
    ;;
esac

echo ""
