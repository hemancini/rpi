#!/bin/bash

# Funciones comunes para los scripts de configuración

source "$(dirname "${BASH_SOURCE[0]}")/../scripts/logging.sh" 2>/dev/null ||
    source "$(dirname "${BASH_SOURCE[0]}")/scripts/logging.sh"

# Asegurarse de que el script se ejecuta como root (excepto check-network.sh)
calling_script=$(basename "${BASH_SOURCE[1]}")
if [[ $EUID -ne 0 && "$calling_script" != "check-network.sh" ]]; then
    log_error "[!] Este script debe ejecutarse como root"
    exit 1
fi

WIFI_SSID_NAT="pi-nat"
WIFI_PASS_NAT="12345678"
WIFI_SSID_BRIDGE="pi-bridge"
WIFI_PASS_BRIDGE="12345678"

RPI_PKGS_NAT="iptables hostapd dnsmasq rfkill dnsutils"
RPI_PKGS_BRIDGE="iptables hostapd dnsmasq bridge-utils rfkill"

# Función para actualizar o crear la variable RPI_NETWORK_MODE en bashrc
update_network_mode() {
    local mode="$1"
    if grep -q "RPI_NETWORK_MODE=" /etc/global_var.conf; then
        sed -i "s|^RPI_NETWORK_MODE=.*|RPI_NETWORK_MODE=\"$mode\"|" /etc/global_var.conf
    else
        echo "RPI_NETWORK_MODE=\"$mode\"" >>/etc/global_var.conf
    fi
    echo "[x] RPI_NETWORK_MODE actualizado a '$mode' en /etc/global_var.conf"
}

# Función para detectar interfaces de red
detect_interfaces() {
    ETHERNET_IF=$(ip -o link show | awk -F': ' '$2 ~ /^e/ {print $2}' | head -n 1)
    WIFI_IF=$(ip -o link show | awk -F': ' '$2 ~ /^w/ {print $2}' | head -n 1)

    # Verificar interfaces disponibles
    if [ -z "$ETHERNET_IF" ] || [ -z "$WIFI_IF" ]; then
        echo "[!] Error: No se pudieron detectar las interfaces de red."
        echo "ETHERNET_IF: $ETHERNET_IF"
        echo "WIFI_IF: $WIFI_IF"
        echo "[x] Interfaces disponibles:"
        ip link show
        exit 1
    fi

    echo "[x] Usando interfaz Ethernet: $ETHERNET_IF"
    echo "[x] Usando interfaz Wi-Fi: $WIFI_IF"
}

enable_ip_forwarding() {
    echo "[x] Habilitando IP forwarding..."
    sed -i '/^#\s*net.ipv4.ip_forward=1/s/^#\s*//' /etc/sysctl.conf
    # cat /etc/sysctl.conf | grep net.ipv4.ip_forward
    sysctl -p
}

# Limpiar configuraciones previas de systemd-networkd
clear_network() {
    echo "[x] Revirtiendo configuraciones de red..."

    echo "[x] Revirtiendo IP forwarding..."
    sed -i '/^[^#]*net.ipv4.ip_forward=1/s/^/#/' /etc/sysctl.conf

    # echo "Deteniendo y deshabilitando servicios de red..."
    # systemctl stop hostapd dnsmasq systemd-networkd NetworkManager wpa_supplicant 2>/dev/null
    # systemctl disable hostapd dnsmasq systemd-networkd NetworkManager wpa_supplicant 2>/dev/null

    # Asegurarse de que no haya otras instancias de dnsmasq en ejecución
    # killall dnsmasq || true

    # Asegurar que la interfaz Wi-Fi no esté bloqueada
    rfkill unblock wifi

    echo "[x] Limpiando configuraciones previas de systemd-networkd..."
    rm -f /etc/systemd/network/*.network
    rm -f /etc/systemd/network/*.netdev

    echo "[x] Limpiando configuraciones previas de hostapd..."
    rm -f /etc/default/hostapd
    rm -f /etc/hostapd/hostapd.conf

    echo "[x] Limpiar cualquier configuración DNS previa de dnsmasq..."
    rm -f /etc/dnsmasq.conf

    echo "[x] Limpiando reglas iptables..."
    sudo netfilter-persistent flush
    # echo "Restablecer todas las reglas de iptables..."
    # iptables -F              # Elimina todas las reglas en las cadenas estándar
    # iptables -t nat -F       # Limpia la tabla NAT
    # iptables -X              # Borra cadenas personalizadas
    # iptables -t nat -X       # Borra cadenas personalizadas en NAT
    # iptables -P INPUT ACCEPT # Establece políticas predeterminadas (cambia a DROP si es necesario)
    # iptables -P FORWARD ACCEPT
    # iptables -P OUTPUT ACCEPT
    # # Elimina la regla de reenvío para tráfico ESTABLISHED/RELATED (3er comando original)
    # iptables -D FORWARD -i $ETHERNET_IF -o $WIFI_IF -m state --state RELATED,ESTABLISHED -j ACCEPT
    # # Elimina la regla de reenvío desde Wi-Fi hacia Ethernet (2do comando original)
    # iptables -D FORWARD -i $WIFI_IF -o $ETHERNET_IF -j ACCEPT
    # # Elimina la regla de MASQUERADE/NAT (1er comando original)
    # iptables -t nat -D POSTROUTING -o $ETHERNET_IF -j MASQUERADE

    echo "[x] Limpiando puente de red $WIFI_IF y $ETHERNET_IF..."
    brctl delif br0 $WIFI_IF || true
    brctl delif br0 $ETHERNET_IF || true
    ip link set dev br0 down || true
    brctl delbr br0 || true

    echo "[x] Limpiando configuraciones previas de $WIFI_IF..."
    ip link set dev $WIFI_IF down || true
    ip addr flush dev $WIFI_IF

    echo "[x] Configuraciones de red revertidas."
}

# Instalar iptables-persistent
install_iptables_persistent() {
    echo "Instalando iptables-persistent..."
    if ! dpkg -l | grep -q "iptables-persistent"; then
        echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | sudo debconf-set-selections
        echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | sudo debconf-set-selections
        apt install -y iptables-persistent
    else
        echo "- iptables-persistent ya está instalado."
    fi
}

# Guardar reglas de iptables de forma persistente
save_iptables_persistent() {
    netfilter-persistent save
}

# Instalar paquetes requeridos
install_packages() {
    DEBIAN_FRONTEND=noninteractive # Evitar preguntas interactivas durante la instalación
    local RPI_PKGS="${1:-$RPI_PKGS_NAT}"
    local UPGRADE=false
    echo "[x] Verificando paquetes requeridos..."

    # Identificar paquetes faltantes
    local missing_pkgs=()
    for pkg in $RPI_PKGS; do
        if ! dpkg -l | grep -q "^ii  $pkg "; then
            echo "- $pkg no está instalado."
            missing_pkgs+=("$pkg")
            # Si el paquete es 'git' o 'nginx', marcar para actualizar
            if [[ "$pkg" == "git" || "$pkg" == "nginx" ]]; then
                UPGRADE=true
            fi
        else
            echo "- $pkg ya está instalado."
        fi
    done

    # Instalar paquetes faltantes si los hay
    if [ ${#missing_pkgs[@]} -gt 0 ]; then
        echo "[x] Instalando paquetes faltantes: ${missing_pkgs[*]}..."
        apt update
        if [ "$UPGRADE" = true ]; then
            echo "[x] Instalando las nuevas versiones de los paquetes..."
            apt upgrade -y
        fi
        apt install -y "${missing_pkgs[@]}"
    else
        echo "[x] Todos los paquetes requeridos están instalados."
    fi
}
