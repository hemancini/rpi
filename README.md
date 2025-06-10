# Configuración y Gestión de Raspberry Pi OS Lite

Un sistema completo para transformar tu Raspberry Pi en un punto de acceso versátil con gestión web integrada, configuración automatizada y capacidades de control de tráfico.

## 📋 Características Principales

### 🌐 Modos de Red Configurables
- **Modo NAT**: Red aislada con bloqueo de dominios y control total del tráfico
- **Modo Bridge**: Integración transparente con la red existente
- **Reversión completa**: Vuelta al estado original del sistema

### 🔧 Gestión Web Avanzada
- **Bash Runner**: Ejecuta comandos directamente desde el navegador
- **Explorador de archivos**: Navega y gestiona el sistema de archivos
- **Monitoreo en tiempo real**: Visualización de logs y estado del sistema
- **Interfaz PS4**: Página optimizada para navegadores de PlayStation

### 🚀 Automatización Completa
- **Despliegue automático**: Configuración inicial con un solo comando
- **Instalación de dependencias**: Gestión automática de paquetes
- **Configuración de servicios**: Setup completo de red y servicios web

### 🛡️ Control de Tráfico
- **Bloqueo de dominios**: Control parental y filtrado de contenido
- **Listas personalizables**: PlayStation, Nintendo y dominios personalizados
- **DNS personalizado**: Redirección de tráfico específico

## 🏗️ Estructura del Proyecto

```
├── rpi.sh                          # Script principal de despliegue
├── scripts/                        # Utilidades del sistema
│   ├── test-host.sh                # Verificación de conectividad
│   ├── logging.sh                  # Sistema de logging
│   ├── install-oh-my-zsh.sh        # Personalización del shell
│   ├── install-locales.sh          # Configuración de idioma
│   ├── crear-alias.sh              # Creación de alias
│   └── clear-known-hosts.sh        # Limpieza de hosts conocidos
├── internet/                       # Configuración de red
│   ├── common-functions.sh         # Funciones compartidas
│   ├── setup-nat-mode.sh           # Configuración modo NAT
│   ├── setup-bridge-mode.sh        # Configuración modo Bridge
│   ├── setup-internet-share.sh     # Selector de modo
│   ├── revert-*.sh                 # Scripts de reversión
│   ├── check-network.sh            # Diagnóstico de red
│   └── dominios/                   # Listas de bloqueo
│       ├── playstation.txt         # Dominios de PlayStation
│       └── nintendo.txt            # Dominios de Nintendo
└── php/                            # Aplicación web
    ├── index.php                   # Backend PHP
    ├── style.css                   # Estilos de la interfaz
    ├── scripts.js                  # Lógica del cliente
    ├── ps4.html                    # Interfaz para PS4
    ├── setup.sh                    # Instalador web
    └── bashrunner.service          # Servicio systemd
```

## 🚀 Inicio Rápido

### Prerrequisitos
- Raspberry Pi con Raspberry Pi OS Lite
- Acceso SSH configurado
- `sshpass` instalado en la máquina de desarrollo (opcional)

### Instalación Automática

**Desde tu máquina de desarrollo:**
```bash
# Clona o descarga el proyecto
git clone <repository-url>
cd "rpi"

# Ejecuta el script principal
./rpi.sh
```

**En la Raspberry Pi (vía SSH):**
```bash
# Configura el modo de red deseado
cd ~/internet
sudo bash setup-internet-share.sh

# Opcional: Instala la interfaz web
cd ~/php
sudo bash setup.sh
```

### Configuración Manual

Si prefieres configurar manualmente:

```bash
# Conectar a la Raspberry Pi
ssh pi@pi.local

# Configurar modo NAT
sudo bash ~/internet/setup-nat-mode.sh

# O configurar modo Bridge
sudo bash ~/internet/setup-bridge-mode.sh

# Instalar interfaz web
sudo bash ~/php/setup.sh
```

## 🌐 Modos de Red

### Modo NAT
- **Red Wi-Fi**: 192.168.4.0/24
- **Gateway**: 192.168.4.1
- **DHCP**: 192.168.4.2-192.168.4.20
- **Características**:
  - Bloqueo de dominios (Google, Facebook, PlayStation, etc.)
  - Control total del tráfico
  - DNS personalizado
  - Ideal para aislamiento y control parental

### Modo Bridge
- **Red**: Misma subred que la red principal
- **DHCP**: Gestionado por el router principal
- **Características**:
  - Integración transparente
  - Sin bloqueo de dominios
  - Máximo rendimiento
  - Ideal para extensión de cobertura

## 🖥️ Interfaz Web

Accede a la interfaz web a través de la IP de tu Raspberry Pi:

- **General**: `http://IP_DE_TU_PI`
- **PS4**: `http://IP_DE_TU_PI` (detección automática)

### Funcionalidades
- ✅ Ejecutar comandos bash
- ✅ Explorar sistema de archivos
- ✅ Visualizar logs en tiempo real
- ✅ Monitoreo de servicios
- ✅ Gestión de archivos

## 🛠️ Comandos Útiles

```bash
# Verificar estado de la red
bash ~/internet/check-network.sh

# Revertir configuración actual
sudo bash ~/internet/revert-internet-share.sh

# Verificar conectividad
bash ~/scripts/test-host.sh

# Ver logs del sistema
journalctl -f

# Estado de servicios
systemctl status hostapd dnsmasq nginx
```

## 🔧 Personalización

### Modificar Configuración de Wi-Fi
Edita las variables en `internet/common-functions.sh`:
```bash
WIFI_SSID_NAT="tu-red-nat"
WIFI_PASS_NAT="tu-contraseña"
WIFI_SSID_BRIDGE="tu-red-bridge"
WIFI_PASS_BRIDGE="tu-contraseña"
```

### Agregar Dominios Bloqueados
Edita `internet/dominios/playstation.txt` o crea nuevos archivos:
```
# Agregar dominios a bloquear
ejemplo.com
*.social-media.com
actualizaciones.fabricante.com
```

### Personalizar Interfaz Web
- **Estilos**: Modifica `php/style.css`
- **Funcionalidad**: Edita `php/scripts.js`
- **Backend**: Personaliza `php/index.php`

## 🔍 Diagnóstico y Solución de Problemas

### Verificar Estado de Servicios
```bash
# Servicios de red
systemctl status hostapd dnsmasq dhcpcd

# Interfaz web
systemctl status nginx php*-fpm

# Logs específicos
journalctl -u hostapd -f
journalctl -u dnsmasq -f
```

### Problemas Comunes

**No hay conectividad Wi-Fi:**
```bash
# Desbloquear Wi-Fi
sudo rfkill unblock wifi

# Reiniciar servicios
sudo systemctl restart hostapd dnsmasq
```

**Interfaz web no accesible:**
```bash
# Verificar nginx
sudo systemctl status nginx

# Verificar PHP
sudo systemctl status php*-fpm

# Revisar logs
sudo tail -f /var/log/nginx/error.log
```

**Sin internet en modo NAT:**
```bash
# Verificar IP forwarding
cat /proc/sys/net/ipv4/ip_forward

# Verificar reglas iptables
sudo iptables -L -n -v
sudo iptables -t nat -L -n -v
```

## 🔄 Reversión

Para volver al estado original del sistema:

```bash
# Reversión completa
sudo bash ~/internet/revert-internet-share.sh

# Reversión específica
sudo bash ~/internet/revert-nat-mode.sh
sudo bash ~/internet/revert-bridge-mode.sh
```

## 📚 Scripts de Utilidad

| Script | Descripción |
|--------|-------------|
| `rpi.sh` | Despliegue principal desde máquina de desarrollo |
| `scripts/test-host.sh` | Verificación de conectividad SSH |
| `scripts/logging.sh` | Sistema de logging con colores |
| `scripts/install-oh-my-zsh.sh` | Instalación de Oh My Zsh |
| `internet/check-network.sh` | Diagnóstico completo de red |
| `php/setup.sh` | Configuración del servidor web |

## 🤝 Contribución

Las contribuciones son bienvenidas. Por favor:

1. Fork el proyecto
2. Crea una rama para tu feature (`git checkout -b feature/AmazingFeature`)
3. Commit tus cambios (`git commit -m 'Add some AmazingFeature'`)
4. Push a la rama (`git push origin feature/AmazingFeature`)
5. Abre un Pull Request

## 📄 Licencia

Este proyecto está bajo la Licencia MIT - ver el archivo LICENSE para detalles.

## ⚠️ Advertencias

- **Seguridad**: Cambia las contraseñas por defecto antes del uso en producción
- **Red**: El modo NAT puede afectar el rendimiento en comparación con Bridge
- **Actualizaciones**: El bloqueo de dominios puede interferir con actualizaciones legítimas
- **Backup**: Realiza copias de seguridad antes de aplicar configuraciones

## 📞 Soporte

Si encuentras problemas:

1. Revisa la sección de diagnóstico
2. Ejecuta `internet/check-network.sh` para obtener información del sistema
3. Consulta los logs del sistema
4. Abre un issue con la información recopilada

---

**Desarrollado con ❤️ para la comunidad de Raspberry Pi**