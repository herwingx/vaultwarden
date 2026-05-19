#!/bin/bash

# =============================================================================
# 🔐 THE VAULT - SECRET MANAGER (AGE)
# =============================================================================
# Suite de cifrado profesional para Vaultwarden.
# =============================================================================

set -euo pipefail

# --- CARGAR ENTORNO MISE (PORTABILIDAD) ---
export HOME="${HOME:-/home/herwingx}"
export MISE_DATA_DIR="$HOME/.local/share/mise"
export PATH="$HOME/.local/bin:$PATH"
cd "$(dirname "$(dirname "${BASH_SOURCE[0]}")")" || exit 1
eval "$(mise activate bash)" 2>/dev/null || true

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
    echo -e "${MAGENTA}"
    echo "    █▀▀ █▄░█ █▀▀ █▀█ █▄█ █▀█ ▀█▀"
    echo "    ██▄ █░▀█ █▄▄ █▀▄ ░█░ █▀▀ ░█░"
    echo -e "${NC}"
}

# --- FUNCIONES DE LOGGING ---
log_section() { echo -e "\n${BOLD}${CYAN}◈ $1${NC}\n" ; }
log_info()    { echo -e "  ${BLUE}ℹ${NC} $1" ; }
log_success() { echo -e "  ${GREEN}✔${NC} $1" ; }
log_warning() { echo -e "  ${YELLOW}⚠${NC} $1" ; }
log_error()   { echo -e "  ${RED}✖${NC} $1" ; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SECRETS_FILE="$PROJECT_DIR/.env"
ENCRYPTED_FILE="$PROJECT_DIR/.env.age"

# Ubicaciones de clave AGE
AGE_KEY_LOCATIONS=(
    "${AGE_KEY_FILE:-}"
    "$PROJECT_DIR/.age-key"
    "$HOME/.age/vaultwarden.key"
    "/root/.age/vaultwarden.key"
)

# Verificar herramientas
check_age() {
    if ! command -v age &> /dev/null; then
        log_error "AGE no está instalado."
        exit 1
    fi
}

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

get_public_key() {
    local key_file="$1"
    age-keygen -y "$key_file" 2>/dev/null
}

# --- COMANDOS ---

setup_keys() {
    show_banner
    log_section "GENERACIÓN DE CLAVE MAESTRA"
    
    local KEY_DIR="$HOME/.age"
    local KEY_FILE="$KEY_DIR/vaultwarden.key"
    
    if [[ -f "$KEY_FILE" ]]; then
        log_warning "Ya existe una clave activa en: $KEY_FILE"
        read -p "    ¿Deseas sobrescribirla? [s/N]: " -r response
        if [[ ! "$response" =~ ^[Ss]$ ]]; then exit 0 ; fi
    fi
    
    mkdir -p "$KEY_DIR"
    chmod 700 "$KEY_DIR"
    age-keygen -o "$KEY_FILE" 2>/dev/null
    chmod 600 "$KEY_FILE"
    
    log_success "Nueva identidad criptográfica generada."
    show_key
}

show_key() {
    local AGE_KEY
    AGE_KEY=$(find_age_key) || true
    
    if [[ -z "$AGE_KEY" ]]; then
        log_error "No se encontró una clave privada."
        exit 1
    fi
    
    echo -e "\n${YELLOW}${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}${BOLD}║  CLAVE PRIVADA (RESPALDO CRÍTICO)                           ║${NC}"
    echo -e "${YELLOW}${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}\n"
    cat "$AGE_KEY"
    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    log_info "Guarda esto en un lugar seguro (Bitwarden Cloud, Password Manager)."
}

encrypt_secrets() {
    check_age
    log_section "CIFRADO DE SECRETOS"
    
    if [[ ! -f "$SECRETS_FILE" ]]; then
        log_error "Archivo ${CYAN}.env${NC} no encontrado."
        exit 1
    fi
    
    local AGE_KEY
    AGE_KEY=$(find_age_key) || true
    
    if [[ -n "$AGE_KEY" ]]; then
        local PUB_KEY
        PUB_KEY=$(get_public_key "$AGE_KEY")
        log_info "Usando llave: $AGE_KEY"
        if age -r "$PUB_KEY" -o "$ENCRYPTED_FILE" "$SECRETS_FILE"; then
            log_success "Archivo cifrado con éxito: ${GREEN}.env.age${NC}"
            echo ""
            read -p "    ¿Eliminar archivo en texto plano (.env)? [S/n]: " -r response
            response=${response:-S}
            if [[ "$response" =~ ^[Ss]$ ]]; then
                rm "$SECRETS_FILE"
                log_success "Archivo plano eliminado por seguridad."
            fi
        fi
    else
        log_error "Se requiere una IDENTITY KEY para continuar."
        exit 1
    fi
}

decrypt_secrets() {
    check_age
    log_section "DESCIFRADO DE CONFIGURACIÓN"
    
    if [[ ! -f "$ENCRYPTED_FILE" ]]; then
        log_error "No existe el archivo ${RED}.env.age${NC}"
        exit 1
    fi
    
    local AGE_KEY
    AGE_KEY=$(find_age_key) || true
    
    if [[ -n "$AGE_KEY" ]]; then
        if age -d -i "$AGE_KEY" -o "$SECRETS_FILE" "$ENCRYPTED_FILE"; then
            log_success "Configuración restaurada en ${BOLD}.env${NC}"
        fi
    else
        log_error "Identity key no encontrada."
        exit 1
    fi
}

edit_secrets() {
    check_age
    
    local AGE_KEY
    AGE_KEY=$(find_age_key) || true
    
    if [[ -z "$AGE_KEY" ]]; then
        log_error "No se puede editar sin clave de identidad."
        exit 1
    fi

    # Crear temporales seguros
    local TEMP_DECRYPTED
    TEMP_DECRYPTED=$(mktemp)
    local TEMP_ENCRYPTED
    TEMP_ENCRYPTED=$(mktemp)
    trap "rm -f $TEMP_DECRYPTED $TEMP_ENCRYPTED" EXIT

    log_info "Descifrando secretos para edición..."
    if [[ -f "$ENCRYPTED_FILE" ]]; then
        if ! age -d -i "$AGE_KEY" -o "$TEMP_DECRYPTED" "$ENCRYPTED_FILE" 2>/dev/null; then
            log_error "Fallo al descifrar $ENCRYPTED_FILE. ¿Es correcta tu clave AGE?"
            exit 1
        fi
    else
        # Si no existe .env.age, inicializar con la plantilla o vacío
        if [[ -f "$SECRETS_FILE" ]]; then
            cp "$SECRETS_FILE" "$TEMP_DECRYPTED"
        elif [[ -f "$PROJECT_DIR/.env.example" ]]; then
            cp "$PROJECT_DIR/.env.example" "$TEMP_DECRYPTED"
        else
            touch "$TEMP_DECRYPTED"
        fi
    fi

    # Copiar estado inicial para detectar si hubo cambios
    local INITIAL_SHA
    INITIAL_SHA=$(sha256sum "$TEMP_DECRYPTED" | cut -d' ' -f1)

    # Abrir editor
    ${EDITOR:-nano} "$TEMP_DECRYPTED"

    # Verificar si el editor se canceló o falló
    if [[ $? -ne 0 ]]; then
        log_warning "El editor retornó un estado de error. Edición abortada."
        return 1
    fi

    local FINAL_SHA
    FINAL_SHA=$(sha256sum "$TEMP_DECRYPTED" | cut -d' ' -f1)

    if [[ "$INITIAL_SHA" == "$FINAL_SHA" ]]; then
        log_info "No se detectaron cambios. Edición cancelada."
        return 0
    fi

    # Cifrar primero al archivo temporal cifrado para validar que sea correcto
    local PUB_KEY
    PUB_KEY=$(get_public_key "$AGE_KEY")
    
    log_info "Cifrando nuevos secretos..."
    if age -r "$PUB_KEY" -o "$TEMP_ENCRYPTED" "$TEMP_DECRYPTED"; then
        # Operación atómica de reemplazo (Segura frente a cortes de luz/caídas)
        mv "$TEMP_ENCRYPTED" "$ENCRYPTED_FILE"
        log_success "Cambios aplicados y re-cifrados exitosamente en .env.age."
    else
        log_error "Fallo al cifrar los nuevos secretos. Tus secretos originales no han sido alterados."
        exit 1
    fi
}

# --- MAIN ---
case "${1:-}" in
    setup)    setup_keys ;;
    encrypt)  encrypt_secrets ;;
    decrypt)  decrypt_secrets ;;
    edit)     edit_secrets ;;
    show-key) show_key ;;
    *)
        show_banner
        echo "Uso: $0 [comando]"
        echo "  setup      Generar llaves Master"
        echo "  encrypt    Proteger .env -> .env.age"
        echo "  decrypt    Restaurar .env.age -> .env"
        echo "  edit       Modificar secretos de forma segura"
        echo "  show-key   Mostrar llave para backup"
        exit 1
        ;;
esac
