#!/bin/bash

# =============================================================================
# 🔄 VAULTWARDEN - RESTORE SYSTEM
# =============================================================================
# Restaura backup de sistema de archivos (SQLite + adjuntos).
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

# --- CONFIGURACIÓN ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$PROJECT_DIR/data"
BACKUP_FILE="${1:-}"

# Ubicaciones de clave AGE
AGE_KEY_LOCATIONS=(
    "${AGE_KEY_FILE:-}"
    "$PROJECT_DIR/.age-key"
    "$HOME/.age/vaultwarden.key"
    "/root/.age/vaultwarden.key"
)

# --- LOGGING ---
log_info() { echo -e "  ${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "  ${GREEN}✔${NC} $1"; }
log_warning() { echo -e "  ${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "  ${RED}✖${NC} $1"; }
log_section() { echo -e "\n${BOLD}${MAGENTA}◈ $1${NC}\n"; }

show_banner() {
    echo -e "${YELLOW}"
    echo "    █▀█ █▀▀ █▀ ▀█▀ █▀█ █▀█ █▀▀"
    echo "    █▀▄ ██▄ ▄█ ░█░ █▄█ █▀▄ ██▄"
    echo -e "${NC}"
    echo -e "    ${CYAN}System Restore Tool${NC}\n"
}

# --- FUNCIONES ---

find_age_key() {
    for key_path in "${AGE_KEY_LOCATIONS[@]}"; do
        if [[ -n "$key_path" && -f "$key_path" ]]; then
            echo "$key_path"
            return 0
        fi
    done
    return 1
}

check_dependencies() {
    local missing=()
    for cmd in age tar docker; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Faltan dependencias: ${missing[*]}"
        exit 1
    fi
}

validate_input() {
    if [[ -z "$BACKUP_FILE" ]]; then
        log_error "Uso: ./restore.sh <archivo_backup.tar.gz.age>"
        exit 1
    fi
    
    if [[ ! -f "$BACKUP_FILE" ]]; then
        log_error "El archivo no existe: $BACKUP_FILE"
        exit 1
    fi
}

decrypt_backup() {
    log_section "DESCIFRADO"
    
    local keys_found=$(find_age_key)
    DECRYPTED_PATH="/tmp/vw_restore_$(date +%s).tar.gz"
    
    if [[ -n "$keys_found" ]]; then
        log_info "Usando clave: $keys_found"
        if age -d -i "$keys_found" -o "$DECRYPTED_PATH" "$BACKUP_FILE"; then
            log_success "Backup descifrado correctamente."
        else
            log_error "Fallo al descifrar. ¿Es la clave correcta?"
            return 1
        fi
    else
        log_warning "No se encontró archivo de clave. Intentando modo passphrase..."
        if age -d -o "$DECRYPTED_PATH" "$BACKUP_FILE"; then
            log_success "Backup descifrado."
        else
            log_error "Fallo al descifrar."
            return 1
        fi
    fi
}

perform_restore() {
    log_section "RESTAURACIÓN"
    
    # 1. Detener Vaultwarden
    log_info "Deteniendo contenedor Vaultwarden..."
    if docker stop vaultwarden; then
        log_success "Contenedor detenido."
    else
        log_warning "No se pudo detener el contenedor (¿ya estaba detenido?)"
    fi
    
    # 2. Backup de seguridad
    if [[ -d "$DATA_DIR" ]]; then
        local safe_backup="${DATA_DIR}_pre_restore_$(date +%Y%m%d_%H%M%S)"
        log_info "Creando respaldo de seguridad del estado actual..."
        log_info "Moviendo data/ -> $safe_backup"
        mv "$DATA_DIR" "$safe_backup"
    fi
    
    # 3. Restaurar
    log_info "Restaurando archivos..."
    mkdir -p "$DATA_DIR"
    
    if tar -xzf "$DECRYPTED_PATH" -C "$DATA_DIR"; then
        log_success "Archivos extraídos: sqlite3, attachments, config..."
    else
        log_error "Fallo al descomprimir el backup."
        # Rollback simple?
        return 1
    fi
    
    # 4. Verificar db
    if [[ ! -f "$DATA_DIR/db.sqlite3" ]]; then
        log_error "ALERTA: El backup no contiene db.sqlite3"
    fi
    
    # 5. Iniciar
    log_info "Iniciando Vaultwarden..."
    if docker start vaultwarden; then
        log_success "Contenedor iniciado."
    else
        log_error "Fallo al iniciar contenedor."
        return 1
    fi
}

cleanup() {
    if [[ -n "${DECRYPTED_PATH:-}" ]]; then
        rm -f "$DECRYPTED_PATH"
    fi
}

# --- EJECUCIÓN ---
trap cleanup EXIT
show_banner
validate_input
check_dependencies
decrypt_backup
perform_restore

log_section "FINALIZADO"
log_success "Restauración completada. Revisa los logs si hubo errores."
echo -e "\n${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
