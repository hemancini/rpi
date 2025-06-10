#!/bin/bash

# Este script configura la Raspberry Pi para actuar como un punto de acceso Wi-Fi con NAT (Network Address Translation)
# bloqueando el acceso a ciertos dominios (Google, Facebook, TikTok, YouTube).

# Verificar interfaces
source "$(dirname "${BASH_SOURCE[0]}")/common-functions.sh"
detect_interfaces

# Variable para habilitar 5GHz (establecer a "true" para activar)
WIFI_5G_ENABLED="false"
WIFI_SSID="${WIFI_SSID_NAT:-"pi-nat"}"
WIFI_PASS="${WIFI_PASS_NAT:-"12345678"}"

# Instalar paquetes necesarios
RPI_PKGS=$RPI_PKGS_NAT
install_packages "$RPI_PKGS"

# Instalar iptables-persistent
install_iptables_persistent

# Limpiar configuraciones previas de red
clear_network

# Configuración para modo NAT
echo "Configurando modo NAT..."
update_network_mode "nat"

# Configurar IP estática para la interfaz Wi-Fi
cat >/etc/systemd/network/10-wifi.network <<EOF
[Match]
Name=$WIFI_IF

[Network]
Address=192.168.4.1/24
EOF

# Configurar hostapd (punto de acceso Wi-Fi) basado en la configuración 5G
if [ "$WIFI_5G_ENABLED" = "true" ]; then
    # Configuración para 5GHz
    echo "Configurando Wi-Fi en modo 5GHz..."
    cat >/etc/hostapd/hostapd.conf <<EOF
interface=$WIFI_IF
driver=nl80211
ssid=$WIFI_SSID
hw_mode=a
channel=36
ieee80211n=1
ieee80211ac=1
wmm_enabled=1
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$WIFI_PASS
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
country_code=US
EOF
else
    # Configuración para 2.4GHz (original)
    echo "Configurando Wi-Fi en modo 2.4GHz..."
    cat >/etc/hostapd/hostapd.conf <<EOF
interface=$WIFI_IF
driver=nl80211
ssid=$WIFI_SSID
hw_mode=g
channel=7
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$WIFI_PASS
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
country_code=US
EOF
fi

# Asegurar que hostapd utilice el archivo de configuración
echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' >/etc/default/hostapd

# Configuración dnsmasq con dhcp y bloqueo
cat >/etc/dnsmasq.conf <<EOF
# Interfaz de escucha
interface=$WIFI_IF
bind-interfaces

# Rango DHCP para clientes Wi-Fi
dhcp-range=192.168.4.100,192.168.4.200,255.255.255.0,24h

# Opciones DHCP
dhcp-option=option:router,192.168.4.1
dhcp-option=option:dns-server,192.168.4.1

# Bloqueo de dominios
address=/google.com/0.0.0.0
address=/www.google.com/0.0.0.0
address=/googleapis.com/0.0.0.0
address=/facebook.com/0.0.0.0
address=/www.facebook.com/0.0.0.0
address=/tiktok.com/0.0.0.0
address=/youtube.com/0.0.0.0

# Servidores DNS ascendentes
server=8.8.8.8
server=8.8.4.4

# Configuraciones adicionales
no-resolv
domain-needed
bogus-priv
cache-size=1000
EOF

# Configurar IP estática para wlan0
cat >/etc/dhcpcd.conf <<EOF
interface eth0
static ip_address=192.168.0.10/24
static routers=192.168.0.1
static domain_name_servers=8.8.8.8 8.8.4.4

interface wlan0
static ip_address=192.168.4.1/24
nohook wpa_supplicant
EOF

# "Habilitando IP forwarding..."
enable_ip_forwarding

echo "Configurando NAT y reglas de iptables..."
iptables -t nat -A POSTROUTING -o $ETHERNET_IF -j MASQUERADE
iptables -A FORWARD -i $ETHERNET_IF -o $WIFI_IF -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i $WIFI_IF -o $ETHERNET_IF -j ACCEPT

# Guardar reglas de IPTables
save_iptables_persistent

echo "Levantando interfaz Wi-Fi..."
ip link set dev $WIFI_IF up
ip addr add 192.168.4.1/24 dev $WIFI_IF

# Habilitar servicios
systemctl unmask hostapd
systemctl enable hostapd
systemctl enable dnsmasq
systemctl enable systemd-networkd

echo "Iniciando servicios de red..."
systemctl restart systemd-networkd

echo "Iniciando dnsmasq..."
systemctl restart dnsmasq

echo "Iniciando hostapd..."
systemctl restart hostapd

# Verificar servicios
echo -e "\nVerificando estado de servicios..."
systemctl status hostapd dnsmasq systemd-networkd --no-pager

# Verificar configuración IP
echo -e "\nConfiguración IP de $WIFI_IF:"
ip addr show $WIFI_IF | grep "inet "

# Verificar DHCP
echo -e "\nEstado de DHCP (dnsmasq):"
netstat -anu | grep ":53 "

# Mostrar resumen
echo -e "\n==============================================="
echo " CONFIGURACIÓN NAT COMPLETADA!"
echo "==============================================="
echo "SSID: $WIFI_SSID"
echo "Contraseña: $WIFI_PASS"
echo ""
echo "MODO NAT:"
echo " - Red Wi-Fi: 192.168.4.0/24"
echo " - Gateway: 192.168.4.1"
echo " - DNS: 192.168.4.1"
echo " - CON bloqueo de dominios (Google, Facebook, TikTok, YouTube)"
echo " - Para verificar bloqueo: nslookup google.com"
echo ""
echo "Recomendación: Cambie la contraseña en /etc/hostapd/hostapd.conf"
echo "==============================================="
