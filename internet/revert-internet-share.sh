#!/bin/bash

# Functions comunes
source "$(dirname "${BASH_SOURCE[0]}")/common-functions.sh"

# RPI_NETWORK_MODE
source /etc/global_var.conf
echo "Network mode: $RPI_NETWORK_MODE"

# Si el modo es Bridge, revertir configuración de Bridge
if [[ "$RPI_NETWORK_MODE" == "bridge" ]]; then
  echo "[x] Revirtiendo configuración de modo Bridge..."
  source "$(dirname "${BASH_SOURCE[0]}")/revert-bridge-mode.sh"
elif [[ "$RPI_NETWORK_MODE" == "nat" ]]; then
  echo "[x] Revirtiendo configuración de modo NAT..."
  source "$(dirname "${BASH_SOURCE[0]}")/revert-nat-mode.sh"
else
  echo "[!] Modo de red desconocido: $RPI_NETWORK_MODE. No se realizará ninguna acción."
fi
