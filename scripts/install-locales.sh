#!/bin/bash

# Script para solucionar el warning: cannot change locale (en_US.UTF-8)
# Debe ejecutarse con sudo o como root

# Asegurarse de que el script se ejecuta como root
if [[ $EUID -ne 0 ]]; then
    echo "Este script debe ejecutarse como root"
    exit 1
fi

# Verificar si la salida contiene "Cannot set"
locale_output=$(locale 2>&1)
if [[ ! $locale_output == *"Cannot set"* ]]; then
    echo "El paquete locales ya está instalado."
    exit 0
fi

echo "Instalando paquete locales..."
apt install -y locales

echo "Configurando en_US.UTF-8 en /etc/locale.gen..."
sed -i '/en_US.UTF-8/s/^#//g' /etc/locale.gen

echo "Generando locales..."
locale-gen

echo "Configurando locale por defecto..."
update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

echo "Locales configurados correctamente."
