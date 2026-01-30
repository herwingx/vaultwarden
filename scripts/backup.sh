#!/bin/bash

# =============================================================================
# ☁️ VAULTWARDEN - HYBRID BACKUP SYSTEM
# =============================================================================
# 1. System Backup (SQLite, Attachments, Config) -> For full self-hosted restore
# 2. JSON Export (Bitwarden Compatible) -> For cloud migration/portability
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

# --- CONFIGURACIÓN DE DIRECTORIOS ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$PROJECT_DIR/data"
SECRETS_FILE="$PROJECT_DIR/.env.age"
LOG_FILE="/var/log/vaultwarden_backup.log"
CONTAINER_NAME="vaultwarden"

# Ajuste de log si no hay permisos
if [[ ! -w "$(dirname "$LOG_FILE")" ]]; then
    LOG_FILE="$PROJECT_DIR/backup.log"
fi

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_ARCHIVE="/tmp/vw_backup_${TIMESTAMP}.tar.gz"
BACKUP_ENCRYPTED="/tmp/vw_backup_${TIMESTAMP}.tar.gz.age"

# Ubicaciones de clave AGE
AGE_KEY_LOCATIONS=(
    "${AGE_KEY_FILE:-}"
    "$PROJECT_DIR/.age-key"
    "$HOME/.age/vaultwarden.key"
    "/root/.age/vaultwarden.key"
)

# --- SISTEMA DE LOGGING ---
log_to_file() {
    local level="$1"
    local message="$2"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

log_section() { 
    echo -e "\n${BOLD}${MAGENTA}◈ $1${NC}\n"
    log_to_file "SECTION" "$1"
}

log_info() { 
    echo -e "  ${BLUE}ℹ${NC} $1"
    log_to_file "INFO" "$1"
}

log_success() { 
    echo -e "  ${GREEN}✔${NC} $1"
    log_to_file "SUCCESS" "$1"
}

log_warning() { 
    echo -e "  ${YELLOW}⚠${NC} $1"
    log_to_file "WARNING" "$1"
}

log_error() { 
    echo -e "  ${RED}✖${NC} $1"
    log_to_file "ERROR" "$1"
}

# --- BANNER ---
show_banner() {
    echo -e "${YELLOW}"
    echo "    █░█ █▄▀ █▄▄ ▄▀█ █▀▀ █▄▀ █░█ █▀█"
    echo "    █▀█ █░█ █▄█ █▀█ █▄▄ █░█ █▄█ █▀▀"
    echo -e "${NC}"
    echo -e "    ${CYAN}Hybrid Backup System (System + JSON)${NC}\n"
}

# --- PREPARACIÓN DEL ENTORNO ---
prepare_environment() {
    export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

    # Encontrar Node/NVM para Bitwarden CLI
    local NVM_DIRS=(
        "$HOME/.nvm/versions/node"
        "/root/.nvm/versions/node"
        "/home/${USER:-}/.nvm/versions/node"
    )
    for NVM_DIR in "${NVM_DIRS[@]}"; do
        if [[ -d "$NVM_DIR" ]]; then
            local NODE_PATH=$(find "$NVM_DIR" -maxdepth 1 -type d -name "v*" 2>/dev/null | sort -V | tail -1)
            if [[ -n "$NODE_PATH" ]]; then
                export PATH="$NODE_PATH/bin:$PATH"
                break
            fi
        fi
    done

    # 3. Fallback explícito para 'bw' binary
    if ! command -v bw &> /dev/null; then
        for BW_PATH in /usr/local/bin/bw /usr/local/sbin/bw /usr/bin/bw /opt/bitwarden/bw; do
            if [[ -x "$BW_PATH" ]]; then
                export PATH="$(dirname "$BW_PATH"):$PATH"
                break
            fi
        done
    fi

    # Aislamiento de sesión de Bitwarden CLI
    BW_DATA_DIR=$(mktemp -d)
    export BITWARDENCLI_APPDATA_DIR="$BW_DATA_DIR"
}

# --- GESTIÓN DE DEPENDENCIAS ---
check_dependencies() {
    local missing=()
    for cmd in age rclone curl tar docker bw; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Dependencias faltantes: ${missing[*]}"
        log_info "Asegúrate de tener instalado: Docker, Age, Rclone, Curl, Tar, Bitwarden CLI (bw)."
        exit 1
    fi
}

# --- SECRETOS Y CLAVES ---
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
    if [[ ! -f "$SECRETS_FILE" ]]; then
        log_error "Archivo de secretos no encontrado: $SECRETS_FILE"
        exit 1
    fi

    log_info "Descifrando configuración..."
    local AGE_KEY=$(find_age_key) || true
    local DECRYPTED=""

    if [[ -n "$AGE_KEY" ]]; then
        DECRYPTED=$(age -d -i "$AGE_KEY" "$SECRETS_FILE" 2>/dev/null)
    elif [[ -n "${AGE_PASSPHRASE:-}" ]]; then
        local PASS_FIFO=$(mktemp -u)
        mkfifo -m 600 "$PASS_FIFO"
        echo "$AGE_PASSPHRASE" > "$PASS_FIFO" &
        DECRYPTED=$(age -d "$SECRETS_FILE" < "$PASS_FIFO" 2>/dev/null)
        rm -f "$PASS_FIFO"
    else
        DECRYPTED=$(age -d "$SECRETS_FILE" 2>/dev/null) || true
    fi

    if [[ -z "$DECRYPTED" ]]; then
        log_error "No se pudo descifrar .env.age. Verifica tu clave AGE."
        exit 1
    fi

    while IFS='=' read -r key value || [[ -n "$key" ]]; do
        [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
        export "$(echo "$key" | xargs)=$(echo "$value" | xargs)"
    done <<< "$DECRYPTED"
    
    log_success "Secretos cargados."
}

# --- BACKUP JSON (COMPATIBILIDAD) ---
export_json_backup() {
    local output_file="$1/vault_export.json"
    log_info "Generando exportación JSON portátil..."

    if [[ -z "${BW_HOST:-}" ]] || [[ -z "${BW_CLIENTID:-}" ]] || [[ -z "${BW_CLIENTSECRET:-}" ]]; then
        log_warning "Faltan credenciales (BW_HOST, BW_CLIENTID...) para exportación JSON. Saltando paso."
        return 0
    fi

    # 1. Config Server
    if ! bw config server "$BW_HOST" > /dev/null 2>&1; then
        log_warning "Fallo al configurar servidor BW. Saltando JSON."
        return 0
    fi

    # 2. Login
    export BW_CLIENTID="$BW_CLIENTID"
    export BW_CLIENTSECRET="$BW_CLIENTSECRET"
    if ! bw login --apikey > /dev/null 2>&1; then
        log_warning "Login fallido en BW CLI. Verifique credenciales. Saltando JSON."
        return 0
    fi

    # 3. Unlock
    export BW_PASSWORD="${BW_PASSWORD:-}"
    BW_SESSION=$(bw unlock --passwordenv BW_PASSWORD --raw 2>/dev/null)
    
    if [[ -z "$BW_SESSION" ]]; then
        log_warning "Fallo al desbloquear bóveda (Password incorrecto?). Saltando JSON."
        return 0
    fi
    export BW_SESSION

    # 4. Export
    if bw export --format json --output "$output_file" > /dev/null 2>&1; then
        log_success "Exportación JSON generada con éxito."
    else
        log_warning "Fallo al ejecutar 'bw export'."
    fi
}

# --- CREACIÓN DE BACKUP HÍBRIDO ---
create_backup() {
    log_section "CREANDO BACKUP HÍBRIDO"
    
    if [[ ! -d "$DATA_DIR" ]]; then
        log_error "Directorio de datos no encontrado: $DATA_DIR"
        return 1
    fi

    local temp_dir=$(mktemp -d)
    log_info "Directorio temporal: $temp_dir"

    # 1. Base de datos (System Backup)
    log_info "Respaldando base de datos..."
    local db_path="$DATA_DIR/db.sqlite3"
    
    # Intentar hot backup usando sqlite3 local si está instalado
    if command -v sqlite3 >/dev/null 2>&1; then
        log_info "Usando sqlite3 local para backup consistente (Hot method)..."
        if sqlite3 "$db_path" ".backup '$temp_dir/db.sqlite3'"; then
            log_success "Hot backup realizado con éxito (sqlite3 .backup)."
        else
            log_warning "Fallo comando sqlite3 local. Copiando archivo directo."
            cp "$db_path" "$temp_dir/db.sqlite3"
        fi
    # Si no hay sqlite3 local, intentar via docker (por si acaso tiene binario)
    elif docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_info "Intentando backup via Docker..."
        if docker exec "$CONTAINER_NAME" sqlite3 /data/db.sqlite3 ".backup '/data/db_backup.sqlite3'" 2>/dev/null; then
            mv "$DATA_DIR/db_backup.sqlite3" "$temp_dir/db.sqlite3"
            log_success "Hot backup realizado via Docker."
        else
            log_warning "No se encontró sqlite3 (ni local ni en docker). Copiando directo."
            cp "$db_path" "$temp_dir/db.sqlite3"
        fi
    else
        log_info "Backup en frío (Cold copy)."
        cp "$db_path" "$temp_dir/db.sqlite3"
    fi

    # 2. Otros archivos del Sistema
    log_info "Copiando adjuntos y configuración..."
    [[ -d "$DATA_DIR/attachments" ]] && cp -r "$DATA_DIR/attachments" "$temp_dir/"
    [[ -f "$DATA_DIR/config.json" ]] && cp "$DATA_DIR/config.json" "$temp_dir/"
    [[ -f "$DATA_DIR/rsa_key.der" ]] && cp "$DATA_DIR/rsa_key.der" "$temp_dir/"
    [[ -f "$DATA_DIR/rsa_key.pub" ]] && cp "$DATA_DIR/rsa_key.pub" "$temp_dir/"

    # 3. Exportación JSON (Portable Backup)
    # Se añade al mismo directorio temporal para ser empaquetado junto
    export_json_backup "$temp_dir"

    # 4. Empaquetar todo
    log_info "Comprimiendo todo en archivo único..."
    tar -czf "$BACKUP_ARCHIVE" -C "$temp_dir" .
    
    rm -rf "$temp_dir"
    
    if [[ -s "$BACKUP_ARCHIVE" ]]; then
        log_success "Archivo maestro creado: $(basename "$BACKUP_ARCHIVE")"
    else
        log_error "El archivo de backup está vacío."
        return 1
    fi
}

# --- CIFRADO ---
encrypt_backup() {
    log_section "CIFRADO AGE"
    
    local AGE_KEY=$(find_age_key)
    local PUB_KEY=""
    
    if [[ -n "$AGE_KEY" ]]; then
        PUB_KEY=$(grep -o 'age1[a-z0-9]*' "$AGE_KEY" | head -1 || age-keygen -y "$AGE_KEY" 2>/dev/null)
    fi

    if [[ -z "$PUB_KEY" ]]; then
        log_error "No se pudo obtener clave pública."
        return 1
    fi

    if age -r "$PUB_KEY" -o "$BACKUP_ENCRYPTED" "$BACKUP_ARCHIVE"; then
        log_success "Cifrado completado."
        rm -f "$BACKUP_ARCHIVE"
    else
        log_error "Fallo al cifrar."
        return 1
    fi
}

# --- SUBIDA CLOUD ---
upload_to_cloud() {
    log_section "SINCRONIZACIÓN CLOUD"
    
    local remote="${RCLONE_REMOTE:-gdrive:Backups/Vaultwarden}"
    local retention="${BACKUP_RETENTION_DAYS:-7}"
    
    log_info "Destino: $remote"
    
    if rclone copy "$BACKUP_ENCRYPTED" "$remote"; then
        log_success "Carga completa."
        log_info "Limpiando antiguos (> ${retention} días)..."
        rclone delete --min-age "${retention}d" "$remote" 2>/dev/null || true
    else
        log_error "Fallo Rclone."
        return 1
    fi
}

send_telegram() {
    local status="$1"
    local extra="$2"
    
    if [[ -n "${TELEGRAM_TOKEN:-}" ]] && [[ -n "${TELEGRAM_CHAT_ID:-}" ]]; then
        local icon="✅"
        local title="Hybrid Backup Exitoso"
        [[ "$status" == "error" ]] && icon="❌" && title="Backup Fallido"
        
        # Escapado básico de HTML para el mensaje
        local text="<b>$icon Vaultwarden Backup</b>%0A$title%0A$extra"
        
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
            -d "chat_id=${TELEGRAM_CHAT_ID}" \
            -d "text=$text" \
            -d "parse_mode=HTML" > /dev/null 2>&1 || true
    fi
}

cleanup() {
    rm -f "$BACKUP_ARCHIVE" "$BACKUP_ENCRYPTED" 2>/dev/null || true
    [[ -n "${BW_DATA_DIR:-}" ]] && rm -rf "$BW_DATA_DIR"
    [[ -d "$DATA_DIR" ]] && rm -f "$DATA_DIR/db_backup.sqlite3" 2>/dev/null || true
}

# --- EJECUCIÓN ---
trap cleanup EXIT
prepare_environment
show_banner
log_to_file "START" "Iniciando proceso de backup híbrido"
check_dependencies
load_secrets

START_TIME=$(date +%s)

if create_backup && encrypt_backup && upload_to_cloud; then
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    FILE_SIZE=$(du -h "$BACKUP_ENCRYPTED" 2>/dev/null | cut -f1)
    
    log_section "RESUMEN"
    log_success "Proceso completado en ${DURATION}s"
    send_telegram "success" "Tamaño: $FILE_SIZE%0ATiempo: ${DURATION}s"
else
    log_section "RESULTADO FINAL"
    log_error "El proceso ha fallado. Revisa log."
    send_telegram "error" "Revisar servidor"
    exit 1
fi

echo -e "\n${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
