#!/bin/bash

# =============================================================================
# ☁️ VAULTWARDEN - CLOUD BACKUP SYSTEM
# =============================================================================
# Exportación, cifrado AGE y sincronización Cloud (Google Drive/S3/etc).
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
SECRETS_FILE="$PROJECT_DIR/.env.age"
LOG_FILE="/var/log/vaultwarden_backup.log"

# Si no tenemos permisos en /var/log, usar log local
if [[ ! -w "$(dirname "$LOG_FILE")" ]]; then
    LOG_FILE="$PROJECT_DIR/backup.log"
fi

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_JSON="/tmp/vw_backup_${TIMESTAMP}.json"
BACKUP_ENCRYPTED="/tmp/vw_backup_${TIMESTAMP}.json.age"

# Ubicaciones de clave AGE
AGE_KEY_LOCATIONS=(
    "${AGE_KEY_FILE:-}"
    "$PROJECT_DIR/.age-key"
    "$HOME/.age/vaultwarden.key"
    "/root/.age/vaultwarden.key"
)

# --- SISTEMA DE LOGGING ---
# Combina el estilo visual con el guardado en archivo del script robusto
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
    echo "    █▄▄ ▄▀█ █▀▀ █▄▀ █░█ █▀█"
    echo "    █▄█ █▀█ █▄▄ █░█ █▄█ █▀▀"
    echo -e "${NC}"
    echo -e "    ${CYAN}Automated Cloud Backup System${NC}\n"
}

# --- PREPARACIÓN DEL ENTORNO (CRÍTICO) ---
prepare_environment() {
    # 1. Definir PATH para Cron
    export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

    # 2. Buscar Node.js / NVM (Necesario para Bitwarden CLI)
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

    # 3. Fallback para encontrar 'bw'
    if ! command -v bw &> /dev/null; then
        for BW_PATH in /usr/local/bin/bw /usr/local/sbin/bw /usr/bin/bw; do
            if [[ -x "$BW_PATH" ]]; then
                export PATH="$(dirname "$BW_PATH"):$PATH"
                break
            fi
        done
    fi

    # 4. AISLAMIENTO DE SESIÓN (CRUCIAL)
    # Crea un entorno limpio para cada ejecución, evitando conflictos de sesión
    BW_DATA_DIR=$(mktemp -d)
    export BITWARDENCLI_APPDATA_DIR="$BW_DATA_DIR"
}

# --- GESTIÓN DE DEPENDENCIAS ---
check_dependencies() {
    local missing=()
    for cmd in age bw rclone curl; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Dependencias faltantes: ${missing[*]}"
        log_info "Instalar con: apt/dnf install age rclone curl && npm install -g @bitwarden/cli"
        exit 1
    fi
}

# --- LÓGICA DE SECRETOS Y CLAVES ---
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
         # Modo Passphrase seguro con FIFO
        local PASS_FIFO=$(mktemp -u)
        mkfifo -m 600 "$PASS_FIFO"
        echo "$AGE_PASSPHRASE" > "$PASS_FIFO" &
        DECRYPTED=$(age -d "$SECRETS_FILE" < "$PASS_FIFO" 2>/dev/null)
        rm -f "$PASS_FIFO"
    else
        # Intento interactivo o fallo
        DECRYPTED=$(age -d "$SECRETS_FILE" 2>/dev/null) || true
    fi

    if [[ -z "$DECRYPTED" ]]; then
        log_error "No se pudo descifrar .env.age. Verifica tu clave AGE."
        exit 1
    fi

    # Cargar variables
    while IFS='=' read -r key value || [[ -n "$key" ]]; do
        [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
        export "$(echo "$key" | xargs)=$(echo "$value" | xargs)"
    done <<< "$DECRYPTED"
    
    log_success "Secretos cargados en memoria."
}

# --- CORE DEL BACKUP ---
export_vault() {
    log_section "EXPORTACIÓN DE BÓVEDA"
    
    if [[ -z "${BW_HOST:-}" ]]; then
        log_error "BW_HOST no definido."
        return 1
    fi

    # 1. Configurar Servidor
    log_info "Servidor: $BW_HOST"
    if ! bw config server "$BW_HOST" > /dev/null; then
        log_error "Fallo al configurar BW server."
        return 1
    fi

    # 2. Login (API Key)
    if [[ -z "${BW_CLIENTID:-}" ]] || [[ -z "${BW_CLIENTSECRET:-}" ]]; then
        log_error "Credenciales BW_CLIENTID/SECRET faltantes."
        return 1
    fi
    
    log_info "Autenticando con API Key..."
    export BW_CLIENTID="$BW_CLIENTID"
    export BW_CLIENTSECRET="$BW_CLIENTSECRET"
    if ! bw login --apikey; then
        log_error "Login fallido. Verifica API Keys."
        return 1
    fi

    # 3. Unlock (Password)
    log_info "Desencriptando bóveda..."
    export BW_PASSWORD="$BW_PASSWORD"
    BW_SESSION=$(bw unlock --passwordenv BW_PASSWORD --raw 2>/dev/null)
    
    if [[ -z "$BW_SESSION" ]]; then
        log_error "Fallo al desbloquear bóveda. Verifica Master Password."
        return 1
    fi
    export BW_SESSION

    # 4. Exportar
    log_info "Generando JSON..."
    if ! bw export --format json --output "$BACKUP_JSON" > /dev/null 2>&1; then
        log_error "Error en bw export."
        return 1
    fi
    
    # Verificar integridad básica
    if [[ ! -s "$BACKUP_JSON" ]]; then
         log_error "Archivo exportado vacío."
         return 1
    fi

    log_success "Bóveda exportada correctamente."
}

encrypt_backup() {
    log_section "CIFRADO AGE"
    
    local AGE_KEY=$(find_age_key)
    local PUB_KEY
    
    if [[ -n "$AGE_KEY" ]]; then
        # Extraer public key de la private key
        PUB_KEY=$(grep -o 'age1[a-z0-9]*' "$AGE_KEY" | head -1 || age-keygen -y "$AGE_KEY" 2>/dev/null)
    else 
        # Si no hay key file, intentar passphrase (no recomendado para autom)
        log_warning "No se encontró key file, intentando modo legacy..."
        PUB_KEY="" # Fallará si no hay interactividad adecuada, mejor error.
    fi

    if [[ -z "$PUB_KEY" ]]; then
        log_error "No se pudo obtener clave pública para cifrar."
        return 1
    fi

    log_info "Cifrando backup..."
    if age -r "$PUB_KEY" -o "$BACKUP_ENCRYPTED" "$BACKUP_JSON"; then
        log_success "Archivo cifrado creado: $(basename "$BACKUP_ENCRYPTED")"
        rm -f "$BACKUP_JSON" # Borrado seguro inmediato
    else
        log_error "Fallo al cifrar con AGE."
        return 1
    fi
}

upload_to_cloud() {
    log_section "SINCRONIZACIÓN CLOUD"
    
    local remote="${RCLONE_REMOTE:-gdrive:Backups/Vaultwarden}"
    local retention="${BACKUP_RETENTION_DAYS:-7}"
    
    log_info "Destino: $remote"
    
    if rclone copy "$BACKUP_ENCRYPTED" "$remote"; then
        log_success "Carga finalizada correctamente."
        
        log_info "Aplicando retención (${retention} días)..."
        rclone delete --min-age "${retention}d" "$remote" 2>/dev/null || true
    else
        log_error "Fallo en la conexión Rclone."
        return 1
    fi
}

send_telegram() {
    local status="$1"
    local extra="$2"
    
    if [[ -n "${TELEGRAM_TOKEN:-}" ]] && [[ -n "${TELEGRAM_CHAT_ID:-}" ]]; then
        local icon="✅"
        local title="Backup Exitoso"
        if [[ "$status" == "error" ]]; then
            icon="❌"
            title="Backup Fallido"
        fi
        
        local text="<b>$icon Vaultwarden Backup</b>%0A$title%0A$extra"
        
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
            -d "chat_id=${TELEGRAM_CHAT_ID}" \
            -d "text=$text" \
            -d "parse_mode=HTML" > /dev/null 2>&1 || true
    fi
}

cleanup() {
    # Eliminar datos sensibles y temporales pase lo que pase
    rm -f "$BACKUP_JSON" "$BACKUP_ENCRYPTED" 2>/dev/null || true
    
    if [[ -n "${BW_DATA_DIR:-}" ]]; then
        rm -rf "$BW_DATA_DIR" 2>/dev/null || true
    fi
    
    # Intentar logout por si acaso quedó viva la sesión global (no debería con BW_DATA_DIR)
    # bw logout > /dev/null 2>&1 || true
}

# --- EJECUCIÓN ---
trap cleanup EXIT
prepare_environment
show_banner

log_to_file "START" "Iniciando proceso de backup"

check_dependencies
load_secrets

START_TIME=$(date +%s)

if export_vault && encrypt_backup && upload_to_cloud; then
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    FILE_SIZE=$(du -h "$BACKUP_ENCRYPTED" 2>/dev/null | cut -f1)
    
    log_section "RESUMEN"
    log_success "Proceso completado en ${DURATION}s"
    send_telegram "success" "Tamaño: $FILE_SIZE%0ATiempo: ${DURATION}s"
else
    log_section "RESULTADO FINAL"
    log_error "El proceso ha fallado. Revisa $LOG_FILE"
    send_telegram "error" "Revisar logs en servidor"
    exit 1
fi

echo -e "\n${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
