#!/bin/bash

# =============================================================================
# ☁️ VAULTWARDEN - CLOUD BACKUP SYSTEM
# =============================================================================
# Exportación, cifrado AGE y sincronización multicloud.
# =============================================================================

set -euo pipefail

# --- CONFIGURACIÓN DE COLORES ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- BANNER ---
show_banner() {
    echo -e "${YELLOW}"
    echo "    █▄▄ ▄▀█ █▀▀ █▄▀ █░█ █▀█"
    echo "    █▄█ █▀█ █▄▄ █░█ █▄█ █▀▀"
    echo -e "${NC}"
}

# --- FUNCIONES DE LOGGING ---
log_section() { echo -e "\n${BOLD}${MAGENTA}◈ $1${NC}\n" ; }
log_info()    { echo -e "  ${BLUE}ℹ${NC} $1" ; }
log_success() { echo -e "  ${GREEN}✔${NC} $1" ; }
log_warning() { echo -e "  ${YELLOW}⚠${NC} $1" ; }
log_error()   { echo -e "  ${RED}✖${NC} $1" ; }

# --- PATH PARA CRON ---
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

# --- CONFIGURACIÓN ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SECRETS_FILE="$PROJECT_DIR/.env.age"
# Usar log local si no hay permisos para /var/log
LOG_FILE="/var/log/vaultwarden_backup.log"
if [[ ! -w "$(dirname "$LOG_FILE")" ]]; then
    LOG_FILE="$PROJECT_DIR/backup.log"
fi

AGE_KEY_LOCATIONS=(
    "${AGE_KEY_FILE:-}"
    "$PROJECT_DIR/.age-key"
    "$HOME/.age/vaultwarden.key"
    "/root/.age/vaultwarden.key"
)

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_JSON="/tmp/vw_backup_${TIMESTAMP}.json"
BACKUP_ENCRYPTED="/tmp/vw_backup_${TIMESTAMP}.json.age"

# BW_DATA_DIR=$(mktemp -d)
# export BITWARDENCLI_APPDATA_DIR="$BW_DATA_DIR"

# --- LÓGICA ---

check_dependencies() {
    for cmd in age bw rclone curl; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Dependencia faltante: $cmd"
            exit 1
        fi
    done
}

find_age_key() {
    for key_path in "${AGE_KEY_LOCATIONS[@]}"; do
        if [[ -n "$key_path" && -f "$key_path" ]]; then
            echo "$key_path"
            return 0
        fi
    done
    return 1
}

load_secrets() {
    local AGE_KEY
    AGE_KEY=$(find_age_key) || true
    if [[ -z "$AGE_KEY" ]]; then
        log_error "No se encontró clave de identidad AGE."
        exit 1
    fi
    
    local DECRYPTED
    DECRYPTED=$(age -d -i "$AGE_KEY" "$SECRETS_FILE" 2>/dev/null)
    
    while IFS='=' read -r key value || [[ -n "$key" ]]; do
        [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
        export "$(echo "$key" | xargs)=$(echo "$value" | xargs)"
    done <<< "$DECRYPTED"
}

export_vault() {
    log_info "Conectando con Vaultwarden..."
    bw config server "$BW_HOST" > /dev/null
    BW_SESSION=$(BW_CLIENTID="$BW_CLIENTID" BW_CLIENTSECRET="$BW_CLIENTSECRET" bw login --apikey --raw)
    BW_SESSION=$(bw unlock --passwordenv BW_PASSWORD --raw)
    export BW_SESSION
    
    if bw export --format json --output "$BACKUP_JSON" > /dev/null 2>&1; then
        log_success "Bóveda extraída correctamente."
    else
        log_error "Error en la exportación de datos."
        return 1
    fi
}

encrypt_backup() {
    local AGE_KEY
    AGE_KEY=$(find_age_key)
    local PUB_KEY
    PUB_KEY=$(age-keygen -y "$AGE_KEY")
    
    if age -r "$PUB_KEY" -o "$BACKUP_ENCRYPTED" "$BACKUP_JSON"; then
        log_success "Backup cifrado con AGE."
        rm -f "$BACKUP_JSON"
    else
        log_error "Error en el cifrado."
        return 1
    fi
}

upload_to_cloud() {
    local remote="${RCLONE_REMOTE:-gdrive:Backups/Vaultwarden}"
    log_info "Sincronizando con la nube..."
    if rclone copy "$BACKUP_ENCRYPTED" "$remote"; then
        log_success "Carga finalizada en ${CYAN}$remote${NC}"
        rclone delete --min-age "${BACKUP_RETENTION_DAYS:-7}d" "$remote" 2>/dev/null || true
    else
        log_error "Fallo en la sincronización Rclone."
        return 1
    fi
}

cleanup() {
    rm -f "$BACKUP_JSON" "$BACKUP_ENCRYPTED" 2>/dev/null || true
    # rm -rf "$BW_DATA_DIR" 2>/dev/null || true
}

# --- MAIN ---
trap cleanup EXIT
show_banner
log_section "EJECUCIÓN DE RESPALDO"

check_dependencies
load_secrets

if export_vault && encrypt_backup && upload_to_cloud; then
    log_success "Operación completada exitosamente."
    # Notificación Telegram (opcional si variables existen)
    if [[ -n "${TELEGRAM_TOKEN:-}" ]]; then
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
            -d "chat_id=${TELEGRAM_CHAT_ID}" \
            -d "text=✅ <b>Vaultwarden Backup</b> completado con éxito." \
            -d "parse_mode=HTML" > /dev/null 2>&1 || true
    fi
else
    log_error "Error crítico en el proceso de backup."
    exit 1
fi
echo -e "\n${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
