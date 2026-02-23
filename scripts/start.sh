#!/bin/bash

# =============================================================================
# 🚀 VAULTWARDEN - ENGINE START
# =============================================================================
# Iniciador seguro con gestión de secretos volátiles.
# =============================================================================

set -euo pipefail

# --- CARGAR ENTORNO MISE (PORTABILIDAD) ---
# Necesario para que start.sh encuentre 'age' si no está instalado globalmente
export MISE_DATA_DIR="$HOME/.local/share/mise"
export PATH="$HOME/.local/bin:$PATH"
eval "$(mise activate bash)" 2>/dev/null || true

# --- CONFIGURACIÓN DE COLORES ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- BANNER ---
show_banner() {
    clear
    echo -e "${BLUE}"
    echo "    █░░ ▄▀█ █░█ █▄░█ █▀▀ █░█ █▀▀ █▀█"
    echo "    █▄▄ █▀█ █▄█ █░▀█ █▄▄ █▀█ ██▄ █▀▄"
    echo -e "${NC}"
}

# --- FUNCIONES DE LOGGING ---
log_info()    { echo -e "  ${BLUE}ℹ${NC} $1" ; }
log_success() { echo -e "  ${GREEN}✔${NC} $1" ; }
log_error()   { echo -e "  ${RED}✖${NC} $1" ; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SECRETS_FILE="$PROJECT_DIR/.env.age"
ENV_FILE="$PROJECT_DIR/.env"

# Ubicaciones de clave AGE
AGE_KEY_LOCATIONS=(
    "${AGE_KEY_FILE:-}"
    "$PROJECT_DIR/.age-key"
    "$HOME/.age/vaultwarden.key"
    "/root/.age/vaultwarden.key"
)

# Buscar clave
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
    if ! command -v age &> /dev/null || ! command -v docker &> /dev/null; then
        log_error "Faltan dependencias (age / docker)."
        exit 1
    fi
}

decrypt_to_env() {
    if [[ ! -f "$SECRETS_FILE" ]]; then
        if [[ -f "$ENV_FILE" ]]; then
            log_warning "Se detectó .env pero no .env.age."
            log_error "Por seguridad, debes cifrar tu configuración antes de iniciar."
            echo -e "    Ejecuta: ${CYAN}./scripts/manage_secrets.sh encrypt${NC}"
            exit 1
        else
            log_error "No se encontró configuración cifrada (${BOLD}.env.age${NC})."
            echo -e "    ¿Ejecutaste el instalador? (${CYAN}./scripts/install.sh${NC})"
            exit 1
        fi
    fi
    
    local AGE_KEY
    AGE_KEY=$(find_age_key) || true
    
    if [[ -n "$AGE_KEY" ]]; then
        age -d -i "$AGE_KEY" -o "$ENV_FILE" "$SECRETS_FILE"
        log_success "Secretos cargados en entorno volátil."
    else
        log_error "Clave de identidad no encontrada."
        exit 1
    fi
}

cleanup() {
    if [[ -f "$ENV_FILE" ]]; then
        rm -f "$ENV_FILE"
        log_info "Entorno limpiado (Zero-Trace)."
    fi
}

# --- MAIN ---
show_banner
check_deps
trap cleanup EXIT

decrypt_to_env

log_info "Iniciando orquestación Docker..."
cd "$PROJECT_DIR"
docker compose up -d

echo ""
docker compose ps
echo ""
log_success "Vaultwarden está operativo."
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
