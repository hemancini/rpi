#!/bin/bash

# Configuración de colores (opcional)
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Nivel de logging (0: error, 1: warn, 2: info, 3: debug)
LOG_LEVEL=3

# Función para obtener la fecha y hora actual
get_timestamp() {
  echo "$(date '+%Y-%m-%d %H:%M:%S')"
}

# Función para loguear mensajes de DEBUG
log_debug() {
  if [ "$LOG_LEVEL" -ge 3 ]; then
    # echo -e "[$(get_timestamp)] ${BLUE}DEBUG${NC}: $1"
    echo -e "${BLUE}$1${NC}"
  fi
}

# Función para loguear mensajes de INFO
log_info() {
  if [ "$LOG_LEVEL" -ge 2 ]; then
    # echo -e "[$(get_timestamp)] ${GREEN}INFO${NC}: $1"
    echo -e "${GREEN}$1${NC}"
  fi
}

# Función para loguear mensajes de WARN
log_warn() {
  if [ "$LOG_LEVEL" -ge 1 ]; then
    # echo -e "[$(get_timestamp)] ${YELLOW}WARN${NC}: $1" >&2
    echo -e "${YELLOW}$1${NC}" >&2
  fi
}

# Función para loguear mensajes de ERROR
log_error() {
  if [ "$LOG_LEVEL" -ge 0 ]; then
    # echo -e "[$(get_timestamp)] ${RED}ERROR${NC}: $1" >&2
    echo -e "${RED}$1${NC}" >&2
  fi
}
