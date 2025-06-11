#!/bin/bash

# Script para compartir internet desde eth0 a wlan0 en modo NAT
# Crea un punto de acceso WiFi llamado "pi-nat" con contraseña "12345678"
# Bloquea dominios google.com y facebook.com

# Funciones comunes
source "$(dirname "${BASH_SOURCE[0]}")/common-functions.sh"
detect_interfaces # Esta función debe definir ETHERNET_IF y WIFI_IF

DOMAIN_BLOCK_ENABLED="true"
WIFI_5G_ENABLED="true"

WIFI_SSID="${WIFI_SSID_NAT:-"pi-nat"}"
WIFI_PASS="${WIFI_PASS_NAT:-"12345678"}"
STATIC_WIFI_IP="192.168.4.1/24"
STATIC_WIFI_IP_PLAIN=${STATIC_WIFI_IP%%/*} # IP sin CIDR para dnsmasq
DHCP_RANGE_START="192.168.4.2"
DHCP_RANGE_END="192.168.4.20"

USER_HOME=$(eval echo ~${SUDO_USER:-$USER})

echo "[x] Instalando paquetes requeridos para modo NAT..."
install_packages "hostapd dnsmasq dhcpcd5 dnsutils iptables rfkill netfilter-persistent"
# sudo apt -y purge hostapd dnsmasq dhcpcd5 dnsutils iptables rfkill netfilter-persistent

echo "[x] Revirtiendo configuración configuración previa de internet compartido..."
bash "$(dirname "${BASH_SOURCE[0]}")/revert-internet-share.sh"

echo "[x] Configurando modo NAT..."
update_network_mode "nat"

echo "[x] Configurando IP estática para $WIFI_IF en /etc/dhcpcd.conf..."
cat >/etc/dhcpcd.conf <<EOF
# interface $ETHERNET_IF
# static ip_address=192.168.0.10/24
# static routers=192.168.0.1
# static domain_name_servers=8.8.8.8 8.8.4.4

# Configuración para NAT AP ($WIFI_IF) - $STATIC_WIFI_IP
interface $WIFI_IF
static ip_address=$STATIC_WIFI_IP
nohook wpa_supplicant
EOF

echo "[x] Habilitando IP forwarding de forma persistente..."
IP_FORWARD_CONF_FILE="/etc/sysctl.d/99-nat-ip_forward.conf"
if [ ! -f "$IP_FORWARD_CONF_FILE" ] || ! grep -q "net.ipv4.ip_forward=1" "$IP_FORWARD_CONF_FILE"; then
    echo "net.ipv4.ip_forward=1" >"$IP_FORWARD_CONF_FILE"
    sysctl -p "$IP_FORWARD_CONF_FILE"
else
    echo "[i] IP forwarding ya configurado en $IP_FORWARD_CONF_FILE."
    if [ "$(cat /proc/sys/net/ipv4/ip_forward)" -ne 1 ]; then
        sysctl -p "$IP_FORWARD_CONF_FILE"
    fi
fi

echo "[x] Configurando hostapd..."
if [ "$WIFI_5G_ENABLED" = "true" ]; then
    echo "[x] Configurando Wi-Fi en modo 5GHz..."
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
    echo "[x] Configurando Wi-Fi en modo 2.4GHz..."
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

echo "[x] Configurando dnsmasq..."
DNSMASQ_FILE="/etc/dnsmasq.conf"
DNSMASQ_CONTENT=$(
    cat <<EOF
# Interfaz de escucha (solo en la interfaz WiFi AP)
listen-address=127.0.0.1,$STATIC_WIFI_IP_PLAIN
interface=$WIFI_IF
bind-dynamic
except-interface=lo

# No pasar nombres de la WAN al DNS local
bogus-priv
# Rango DHCP
dhcp-range=$DHCP_RANGE_START,$DHCP_RANGE_END,255.255.255.0,24h
domain=wlan

# Opciones DHCP para DNS
dhcp-option=option:dns-server,$STATIC_WIFI_IP_PLAIN
server=8.8.8.8
server=8.8.4.4

# Bloqueo de dominios
address=/google.com/0.0.0.0
address=/facebook.com/0.0.0.0
# address=/playstation.com/192.168.1.236
EOF
)

BASH_DIR="$(dirname "${BASH_SOURCE[0]}")"
PLAY_DOMAINS="${BASH_DIR}/dominios/playstation.txt"
NINTENDO_DOMAINS="${BASH_DIR}/dominios/nintendo.txt"

ALL_DOMAINS="$PLAY_DOMAINS $NINTENDO_DOMAINS"
if [ "$DOMAIN_BLOCK_ENABLED" = "true" ]; then
    DNSMASQ_CONTENT+="\n# Dominios bloqueados desde archivos"
    for domain_file in $ALL_DOMAINS; do
        if [ -f "$domain_file" ] && [ -s "$domain_file" ]; then
            echo "[x] Leyendo dominios desde $domain_file para bloqueos..."
            while IFS= read -r line || [[ -n "$line" ]]; do
                # Ignora líneas vacías y comentarios
                if [[ -z "$line" ]] || [[ "$line" == \#* ]]; then
                    continue
                fi

                # Elimina espacios en blanco al inicio/final (si los hubiera)
                domain=$(echo "$line" | xargs)

                # Añade la entrada de bloqueo al contenido
                if [ -n "$domain" ]; then
                    DNSMASQ_CONTENT+="\naddress=/$domain/$STATIC_WIFI_IP_PLAIN"
                fi
            done <"$domain_file"
        else
            echo "[!] Advertencia: El archivo '$domain_file' no existe o está vacío."
        fi
    done
fi

# Reemplazar el archivo /etc/dnsmasq.conf con el nuevo contenido
echo -e "$DNSMASQ_CONTENT" >"$DNSMASQ_FILE"

echo "[⏳] Configurando reglas de iptables para NAT y acceso WiFi..."

echo "[x] Limpiar reglas específicas existentes de forma segura"
iptables -t nat -D POSTROUTING -o $ETHERNET_IF -j MASQUERADE 2>/dev/null || true
iptables -D FORWARD -i $WIFI_IF -o $ETHERNET_IF -j ACCEPT 2>/dev/null || true

echo "[⏳] Configurar NAT y forwarding"
iptables -t nat -A POSTROUTING -o $ETHERNET_IF -j MASQUERADE
iptables -A FORWARD -i $WIFI_IF -o $ETHERNET_IF -j ACCEPT
iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT

echo "[x] Permitir servicios necesarios para el AP"
iptables -A INPUT -i lo -j ACCEPT 2>/dev/null || true
iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
iptables -A INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null || true
iptables -A INPUT -i $WIFI_IF -p udp --dport 67 -j ACCEPT 2>/dev/null || true
iptables -A INPUT -i $WIFI_IF -p udp --dport 53 -j ACCEPT 2>/dev/null || true
iptables -A INPUT -i $WIFI_IF -p tcp --dport 53 -j ACCEPT 2>/dev/null || true

echo "[x] Guardando reglas de iptables..."
if command -v netfilter-persistent &>/dev/null; then
    netfilter-persistent save
    # netfilter-persistent start
    # systemctl enable netfilter-persistent
else
    echo "[!] Advertencia: No se encontró netfilter-persistent."
fi

echo "[x] Creando servicio para desbloquear rfkill y reiniciar servicios de red..."
cat >"$USER_HOME/init-service.sh" <<EOF
#!/bin/bash

echo "[x] Desbloqueando WiFi con rfkill..."
if command -v rfkill &>/dev/null; then
    sudo rfkill unblock wifi
else
    echo "[!] Advertencia: rfkill no está instalado. No se puede desbloquear WiFi."
fi

echo "[x] Asegurando que la interfaz $WIFI_IF esté activa..."
ip link set dev $WIFI_IF up

echo "[x] Reiniciando hostapd..."
sudo systemctl restart hostapd || true

echo "[x] Configurando NAT y forwarding de iptables..."
sudo iptables -t nat -A POSTROUTING -o $ETHERNET_IF -j MASQUERADE

exit 0
EOF

chmod +x "$USER_HOME/init-service.sh"
chown ${SUDO_USER:-$USER}:${SUDO_USER:-$USER} "$USER_HOME/init-service.sh" 2>/dev/null || true

# crear servicio para ejecutar $USER_HOME/init-service.sh al iniciar el sistema
cat >"/etc/systemd/system/init-service.service" <<EOF
[Unit]
Description=Servicio de inicialización para configurar red y hostapd
After=network.target
[Service]
Type=oneshot
ExecStart=/bin/bash $USER_HOME/init-service.sh
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable init-service.service

echo "[x] Desbloqueando WiFi con rfkill..."
if command -v rfkill &>/dev/null; then
    rfkill unblock wifi
fi

echo "[x] Asegurando que la interfaz $WIFI_IF esté activa..."
ip link set dev $WIFI_IF up

echo "[x] Habilitando servicios..."
systemctl enable dhcpcd
systemctl unmask hostapd
systemctl enable hostapd
systemctl enable dnsmasq

echo "[x] Iniciando servicio dhcpcd..."
systemctl start dhcpcd

echo "[x] Iniciando servicio hostapd..."
systemctl start hostapd

echo "[x] Iniciando servicios dnsmasq..."
systemctl start dnsmasq

# Verificar que los servicios estén corriendo
echo "[x] Verificando estado de servicios..."
for service in dhcpcd hostapd dnsmasq; do
    if systemctl is-active --quiet $service; then
        echo "✓ $service está corriendo"
    else
        echo "⚠ $service no está corriendo, intentando reiniciar..."
        systemctl restart $service
        sleep 2
    fi
done

# obtener IP del host
HOST_IP="$(hostname -I | awk '{print $1}')"
if [ -z "$HOST_IP" ]; then
    echo "[+] Esperando que se asigne la IP del host..."
    for i in {1..10}; do
        sleep 1
        HOST_IP="$(hostname -I | awk '{print $1}')"
        if [ -n "$HOST_IP" ]; then
            break
        fi
    done
fi

if [ -z "$HOST_IP" ]; then
    echo "[!] No se pudo obtener la IP del host inmediatamente. Esto es normal y se resolverá después del reinicio."
    HOST_IP="[Se asignará después del reinicio]"
else
    echo "[x] IP del host obtenida: $HOST_IP"
fi

# Actualizar dnsmasq.conf para playstation.com
SEARCH_VALUE="address=/playstation.com"
NEW_LINE="$SEARCH_VALUE/$HOST_IP"

if grep -q "^$SEARCH_VALUE/" "$DNSMASQ_FILE"; then
    sed -i "s|^$SEARCH_VALUE/.*|$NEW_LINE|" "$DNSMASQ_FILE"
    echo "[x] La configuración para playstation.com ha sido actualizada a $NEW_VALUE"
else
    echo "$NEW_LINE" >>"$DNSMASQ_FILE"
    echo "[x] Se ha agregado una nueva entrada para playstation.com."
fi

# Reiniciar dnsmasq para aplicar los cambios
if systemctl is-active --quiet dnsmasq; then
    systemctl restart dnsmasq
    echo "[x] El servicio dnsmasq ha sido reiniciado para aplicar los cambios."
else
    echo "[x] Nota: El servicio dnsmasq no está activo. Los cambios se aplicarán cuando se inicie."
fi

# Esperar a que la IP esté disponible
echo "[X] Esperando que la IP esté disponible..."
for i in {1..30}; do
    if ip addr show $WIFI_IF | grep -q "$STATIC_WIFI_IP_PLAIN"; then
        echo "✓ IP $STATIC_WIFI_IP_PLAIN detectada en $WIFI_IF"
        break
    fi
    printf "⏳ Esperando... (%d/30)\r" "$i"
    sleep 1
done

if ! ip addr show $WIFI_IF | grep -q "$STATIC_WIFI_IP_PLAIN"; then
    echo "[!] Advertencia: La IP $STATIC_WIFI_IP_PLAIN no se detectó en $WIFI_IF después de 30 segundos."
else
    echo "[x] IP $STATIC_WIFI_IP_PLAIN configurada correctamente en $WIFI_IF"
fi

echo ""
echo "--------------------------------------------------------------------"
echo "Configuración completada."
echo "Punto de acceso WiFi SSID: '$WIFI_SSID'"
echo "Contraseña WiFi: '$WIFI_PASS'"
echo "IP de la Raspberry Pi ($WIFI_IF): $STATIC_WIFI_IP_PLAIN"
echo "Rango DHCP para clientes WiFi: $DHCP_RANGE_START - $DHCP_RANGE_END"
echo "IP del host: $HOST_IP"
echo "Dominios google.com y facebook.com bloqueados."
echo "Servicio 'init-service.service' creado y habilitado."
echo ""
echo "IMPORTANTE:"
echo "1. Reinicia el sistema para aplicar todos los cambios: sudo reboot"
echo "2. Después del reinicio, ejecuta: $USER_HOME/check-network.sh"
echo "3. Si hay problemas, revisa los logs de los servicios"
echo "4. Si pierdes conectividad, ejecuta el script de reversión"
echo "--------------------------------------------------------------------"
echo ""
echo "Para troubleshooting, revisa los logs con:"
echo "  bash /home/pi/check-network.sh"
