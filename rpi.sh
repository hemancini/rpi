#!/bin/bash

# Script para limpiar entradas específicas del archivo known_hosts
bash "$(dirname "${BASH_SOURCE[0]}")/scripts/clear-known-hosts.sh"

# Espera a que el dispositivo Pi esté disponible en la red
bash "$(dirname "${BASH_SOURCE[0]}")/scripts/test-host.sh"

# Copiar la clave pública al dispositivo Pi
sshpass -p 'pi' ssh-copy-id -i ~/.ssh/id_rsa.pub -f -o StrictHostKeyChecking=no pi@pi.local
if [ $? -ne 0 ]; then
  echo "Error al copiar la clave pública. Verifique la conexión con el dispositivo Pi."
  exit 1
fi

# Si la copia de la clave fue exitosa, proceder con la copia de archivos
echo -e "Clave pública copiada exitosamente.\nProcediendo con la copia de archivos..."
scp -r ~/PI-Pwn/Raspberry\ Pi\ OS\ Lite\/internet/* pi@pi.local:/home/pi/
scp -r ~/PI-Pwn/Raspberry\ Pi\ OS\ Lite\/scripts/* pi@pi.local:/home/pi/scripts/
scp -r ~/PI-Pwn/Raspberry\ Pi\ OS\ Lite\/php/* pi@pi.local:/home/pi/php/

# Ejecutar script de configuración en el dispositivo Pi
ssh pi@pi.local 'sudo bash ~/scripts/install-locales.sh'

# Crear alias en el dispositivo Pi
ssh pi@pi.local 'bash ~/scripts/crear-alias.sh'

# Instalar php
echo "Instalando PHP en el dispositivo Pi..."
ssh pi@pi.local 'cd ~/php && sudo bash setup.sh'

# Instalar oh-my-zsh en el dispositivo Pi
# ssh pi@pi.local 'sudo bash ~/scripts/install-oh-my-zsh.sh'
