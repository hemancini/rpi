#!/bin/bash

# Archivo known_hosts
KNOWN_HOSTS_FILE="$HOME/.ssh/known_hosts"

# Patrones a eliminar (deben aparecer al inicio de la línea)
PATTERNS=(
  "^pi\.local ssh-ed25519"
  "^pi\.local ssh-rsa"
  "^pi\.local ecdsa-sha2-nistp256"
)

# Verificar si el archivo existe
if [ ! -f "$KNOWN_HOSTS_FILE" ]; then
  echo "El archivo $KNOWN_HOSTS_FILE no existe."
  exit 1
fi

# Determinar si es macOS para ajustar el comando sed
if [[ "$(uname)" == "Darwin" ]]; then
  SED_COMMAND="sed -i ''"
else
  SED_COMMAND="sed -i"
fi

# Procesar cada patrón
for pattern in "${PATTERNS[@]}"; do
  # Usar sed para eliminar líneas que comiencen con el patrón
  eval "$SED_COMMAND \"/$pattern/d\" \"$KNOWN_HOSTS_FILE\""
done

echo "Líneas no deseadas eliminadas de $KNOWN_HOSTS_FILE"
