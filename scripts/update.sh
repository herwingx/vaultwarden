#!/bin/bash

# =============================================================================
# 🔄 VAULTWARDEN - ACTUALIZAR A LA ÚLTIMA VERSIÓN
# =============================================================================
# Descarga las imágenes Docker más recientes (vaultwarden/server, cloudflared)
# y reinicia los contenedores. Usa el mismo flujo seguro que start.sh.
# =============================================================================

set -euo pipefail

# --- CARGAR ENTORNO MISE ---
export MISE_DATA_DIR="$HOME/.local/share/mise"
export PATH="$HOME/.local/bin:$PATH"
eval "$(mise activate bash)" 2>/dev/null || true

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_info()    { echo -e "  ${BLUE}ℹ${NC} $1" ; }
log_success() { echo -e "  ${GREEN}✔${NC} $1" ; }
log_error()   { echo -e "  ${RED}✖${NC} $1" ; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SECRETS_FILE="$PROJECT_DIR/.env.age"
ENV_FILE="$PROJECT_DIR/.env"

AGE_KEY_LOCATIONS=(
    "${AGE_KEY_FILE:-}"
    "$PROJECT_DIR/.age-key"
    "$HOME/.age/vaultwarden.key"
    "/root/.age/vaultwarden.key"
)

find_age_key() {
    for key_path in "${AGE_KEY_LOCATIONS[@]}"; do
        if [[ -n "$key_path" && -f "$key_path" ]]; then
            echo "$key_path"
            return 0
        fi
    done
    return 1
}

check_deps() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker no está instalado o no está en el PATH."
        exit 1
    fi
    if ! docker compose version &> /dev/null; then
        log_error "Docker Compose no disponible."
        exit 1
    fi
}

decrypt_to_env() {
    if [[ ! -f "$SECRETS_FILE" ]]; then
        if [[ -f "$ENV_FILE" ]]; then
            log_info "Usando .env existente (sin .env.age)."
            return 0
        fi
        log_error "No se encontró .env.age ni .env. Ejecuta: ./scripts/install.sh"
        exit 1
    fi
    local AGE_KEY
    AGE_KEY=$(find_age_key) || true
    if [[ -n "$AGE_KEY" ]]; then
        age -d -i "$AGE_KEY" -o "$ENV_FILE" "$SECRETS_FILE"
        log_success "Secretos cargados."
    else
        log_error "Clave AGE no encontrada (ej. ~/.age/vaultwarden.key)."
        exit 1
    fi
}

cleanup() {
    if [[ -f "$ENV_FILE" && -f "$SECRETS_FILE" ]]; then
        rm -f "$ENV_FILE"
        log_info "Entorno limpiado."
    fi
}

# --- MAIN ---
echo -e "${CYAN}"
echo "    █░█ █▀▀ █░░ █▀▀ █▀█"
echo "    █▄█ ██▄ █▄▄ ██▄ █▀▄  Actualizar imágenes"
echo -e "${NC}"

check_deps
trap cleanup EXIT
decrypt_to_env

cd "$PROJECT_DIR"

log_info "Descargando últimas imágenes (vaultwarden/server, cloudflared)..."
docker compose pull

log_info "Recreando contenedores con las nuevas imágenes..."
docker compose up -d

echo ""
docker compose ps
echo ""
log_success "Actualización completada. Vaultwarden está usando la última imagen disponible."
echo -e "  ${YELLOW}Tip:${NC} Para fijar una versión concreta (ej. 1.35.4), edita ${BOLD}docker-compose.yml${NC} y cambia ${BOLD}image: vaultwarden/server:latest${NC} por ${BOLD}vaultwarden/server:1.35.4${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
