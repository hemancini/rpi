#!/bin/bash

# Definir el alias que queremos agregar
ALIAS_NAME="ll"
ALIAS_VALUE="'ls -l'"

# Verificar si el alias ya existe en el archivo
if grep -q "alias $ALIAS_NAME=" ~/.bashrc; then
  # Si existe, lo actualizamos
  sed -i "s/alias $ALIAS_NAME=.*/alias $ALIAS_NAME=$ALIAS_VALUE/" ~/.bashrc
  echo "Alias '$ALIAS_NAME' actualizado correctamente."
else
  # Si no existe, lo agregamos al final del archivo
  echo "alias $ALIAS_NAME=$ALIAS_VALUE" >>~/.bashrc
  echo "Alias '$ALIAS_NAME' agregado correctamente."
fi

# Aplica los cambios al shell actual
source ~/.bashrc
