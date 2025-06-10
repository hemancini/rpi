#!/bin/bash

# Configuración modo Bridge para Raspberry Pi
# Sin bloqueo de dominios - Solo actúa como puente transparente

set -e # Salir si hay errores

# Funciones comunes
source "$(dirname "${BASH_SOURCE[0]}")/common-functions.sh"
detect_interfaces # Esta función debe definir ETHERNET_IF y WIFI_IF

# Asumiendo que estas variables están definidas en common-functions.sh o aquí
WIFI_SSID_BRIDGE="${WIFI_SSID_BRIDGE:-"pi-bridge"}"
WIFI_PASS_BRIDGE="${WIFI_PASS_BRIDGE:-"12345678"}"

echo "[x] Instalando paquetes requeridos para modo Bridge..."
install_packages "hostapd bridge-utils iptables rfkill netfilter-persistent"
# sudo apt -y purge hostapd bridge-utils iptables rfkill netfilter-persistent

# Cargar módulos necesarios para bridge
echo "[x] Cargando módulos del kernel necesarios para bridge..."
modprobe br_netfilter || echo "[!] No se pudo cargar el módulo br_netfilter"
modprobe bridge || echo "[!] No se pudo cargar el módulo bridge"

# Asegurarse de que los módulos se carguen al inicio
if [ ! -f /etc/modules-load.d/bridge.conf ]; then
  echo "# Cargar módulos bridge al inicio" >/etc/modules-load.d/bridge.conf
  echo "bridge" >>/etc/modules-load.d/bridge.conf
  echo "br_netfilter" >>/etc/modules-load.d/bridge.conf
fi

echo "[x] Revirtiendo configuración de NAT si está activa..."
bash "$(dirname "${BASH_SOURCE[0]}")/revert-internet-share.sh"

echo "[x] Configurando modo Bridge..."
update_network_mode "bridge"

echo "[x] Configurando systemd-networkd para el puente br0..."
cat >/etc/systemd/network/05-br0.netdev <<EOF
[NetDev]
Name=br0
Kind=bridge
EOF

echo "[x] Configurando interfaz Ethernet $ETHERNET_IF para unirse al puente br0..."
cat >/etc/systemd/network/10-$ETHERNET_IF-br0.network <<EOF
[Match]
Name=$ETHERNET_IF

[Network]
Bridge=br0
DHCP=no
LinkLocalAddressing=no
ConfigureWithoutCarrier=yes

[Link]
RequiredForOnline=no
EOF

echo "[x] Configurando interfaz Wi-Fi $WIFI_IF para unirse al puente br0..."
cat >/etc/systemd/network/20-br0-dhcp.network <<EOF
[Match]
Name=br0

[Network]
DHCP=yes
DNS=8.8.8.8 8.8.4.4
ConfigureWithoutCarrier=yes

[DHCP]
RouteMetric=10
UseDNS=yes
UseNTP=yes
SendHostname=yes
UseHostname=yes
UseDomains=yes
RequestBroadcast=true
ClientIdentifier=mac

[Link]
RequiredForOnline=yes
EOF

echo "[x] Configurando hostapd para $WIFI_SSID_BRIDGE..."
cat >/etc/hostapd/hostapd.conf <<EOF
interface=$WIFI_IF
driver=nl80211
bridge=br0
ssid=$WIFI_SSID_BRIDGE
hw_mode=g
channel=7
wmm_enabled=1
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$WIFI_PASS_BRIDGE
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
country_code=US
ieee80211n=1
ieee80211d=1
beacon_int=100
dtim_period=2
max_num_sta=32
EOF

echo "[x] Creando servicio para desbloquear rfkill y reiniciar servicios de red..."
cat >"/home/pi/init-service.sh" <<EOF
#!/bin/bash

set -e # Salir si hay errores

echo "[x] Desbloqueando WiFi con rfkill..."
if command -v rfkill &>/dev/null; then
    sudo rfkill unblock wifi
else
    echo "[!] Advertencia: rfkill no está instalado. No se puede desbloquear WiFi."
fi

echo "[x] Asegurando que la interfaz $WIFI_IF esté activa..."
ip link set dev $WIFI_IF up

sleep 10 # Esperar un momento para que la interfaz se active

echo "[x] Limpiando reglas de iptables..."
sudo iptables -P INPUT ACCEPT 2>/dev/null || true
sudo iptables -P FORWARD ACCEPT 2>/dev/null || true
sudo iptables -P OUTPUT ACCEPT 2>/dev/null || true

echo "[x] Reiniciando dhcpcd..." 
sudo systemctl restart dhcpcd || true

echo "[x] Reiniciando systemd-networkd..."
sudo systemctl restart systemd-networkd || true

echo "[x] Reiniciando hostapd..."
sudo systemctl restart hostapd || true

echo "[x] Reiniciando dnsmasq..."
sudo systemctl restart dnsmasq || true

exit 0
EOF

chmod +x "/home/pi/init-service.sh"

# crear servicio para ejecutar /home/pi/init-service.sh al iniciar el sistema
cat >"/etc/systemd/system/init-service.service" <<EOF
[Unit]
Description=Servicio de inicialización para configurar red y hostapd
After=network.target
[Service]
Type=oneshot
ExecStart=sudo /bin/bash /home/pi/init-service.sh
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable init-service.service

echo "[x] Limpiando reglas de iptables existentes y configurando NAT..."
iptables -X           # Delete: Elimina todas las cadenas definidas por el usuario
iptables -t nat -X    # Delete: Elimina todas las cadenas definidas por el usuario en la tabla NAT
iptables -t nat -Z    # Zero: Pone a cero todos los contadores de paquetes y bytes en la tabla NAT
iptables -t mangle -X # Delete: Elimina todas las cadenas definidas por el usuario en la tabla mangle

echo "[x] Guardando reglas de iptables..."
if command -v netfilter-persistent &>/dev/null; then
  netfilter-persistent save
  # netfilter-persistent start
  # systemctl enable netfilter-persistent
else
  echo "[!] Advertencia: No se encontró netfilter-persistent."
fi

echo "[x] Estableciendo DAEMON_CONF para hostapd..."
if [ -f /etc/default/hostapd ]; then
  sed -i 's|^#DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd
  if ! grep -q 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' /etc/default/hostapd; then
    echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' >>/etc/default/hostapd
  fi
elif [ -f /etc/conf.d/hostapd ]; then
  echo 'DAEMON_OPTS="-dd /etc/hostapd/hostapd.conf"' >/etc/conf.d/hostapd
else
  echo "[!] Advertencia: No se encontró el archivo de configuración por defecto de hostapd."
fi

# Habilitando IP forwarding de forma persistente
echo "[x] Habilitando IP forwarding (persistente)..."
IP_FORWARD_CONF_FILE="/etc/sysctl.d/99-bridge-ip_forward.conf"
if [ ! -f "$IP_FORWARD_CONF_FILE" ] || ! grep -q "net.ipv4.ip_forward=1" "$IP_FORWARD_CONF_FILE"; then
  echo "net.ipv4.ip_forward=1" >"$IP_FORWARD_CONF_FILE"
  sysctl -p "$IP_FORWARD_CONF_FILE"
else
  echo "[x] [i] IP forwarding ya configurado en $IP_FORWARD_CONF_FILE."
  if [ "$(cat /proc/sys/net/ipv4/ip_forward)" -ne 1 ]; then
    sysctl -p "$IP_FORWARD_CONF_FILE"
  fi
fi

# Configuración adicional para puentes - solo si el módulo está cargado
if [ -d "/proc/sys/net/bridge" ]; then
  echo "[x] Configurando parámetros bridge-nf-call..."
  echo "net.bridge.bridge-nf-call-iptables=1" >/etc/sysctl.d/99-bridge-nf.conf
  echo "net.bridge.bridge-nf-call-ip6tables=1" >>/etc/sysctl.d/99-bridge-nf.conf
  echo "net.bridge.bridge-nf-call-arptables=1" >>/etc/sysctl.d/99-bridge-nf.conf
  sysctl -p /etc/sysctl.d/99-bridge-nf.conf || echo "[!] No se pudieron aplicar algunos parámetros bridge-nf-call"
else
  echo "[!] El directorio /proc/sys/net/bridge no existe. Asegúrate de que el módulo br_netfilter esté cargado."
  # Intentar cargar el módulo nuevamente
  modprobe br_netfilter
  sleep 1
  if [ -d "/proc/sys/net/bridge" ]; then
    echo "net.bridge.bridge-nf-call-iptables=1" >/etc/sysctl.d/99-bridge-nf.conf
    echo "net.bridge.bridge-nf-call-ip6tables=1" >>/etc/sysctl.d/99-bridge-nf.conf
    echo "net.bridge.bridge-nf-call-arptables=1" >>/etc/sysctl.d/99-bridge-nf.conf
    sysctl -p /etc/sysctl.d/99-bridge-nf.conf || echo "[!] No se pudieron aplicar algunos parámetros bridge-nf-call después de cargar br_netfilter"
  fi
fi

echo "[x] Habilitando servicios..."
systemctl unmask hostapd
systemctl enable hostapd

echo "[x] Iniciando servicio systemd-networkd..."
systemctl enable systemd-networkd

echo "[x] Reiniciando servicio hostapd..."
systemctl restart hostapd

echo "[x] Levantando interfaz Wi-Fi..."
ip link set dev $WIFI_IF up || true # Ignorar error si la interfaz ya está activa

echo "[x] Reiniciando servicio systemd-networkd..."
systemctl restart systemd-networkd

# obtener IP del host
HOST_IP="$(hostname -I | awk '{print $1}')"
# esperar 30 segundos como máximo para que se asigne la IP
if [ -z "$HOST_IP" ]; then
  echo "[+] Esperando que se asigne la IP del host..."
  for i in {1..30}; do
    sleep 1
    HOST_IP="$(hostname -I | awk '{print $1}')"
    if [ -n "$HOST_IP" ]; then
      break
    fi
  done
fi
if [ -z "$HOST_IP" ]; then
  log_error "No se pudo obtener la IP del host después de 30 segundos. Abortando."
  exit 1
fi
echo "[x] IP del host obtenida: $HOST_IP"

# Mostrar resumen
echo "==============================================="
echo " CONFIGURACIÓN BRIDGE COMPLETADA!"
echo "==============================================="
echo "SSID: $WIFI_SSID_BRIDGE"
echo "Contraseña: $WIFI_PASS_BRIDGE"
echo "IP del host: $HOST_IP"
echo ""
echo "MODO BRIDGE:"
echo " - Todos los dispositivos en la misma red"
echo " - Router principal asigna IPs"
echo ""
echo "Recomendación: Cambie la contraseña en /etc/hostapd/hostapd.conf"
echo "==============================================="
echo ""
echo "Scripts de ayuda creados:"
echo "  bash /home/pi/check-network.sh"
