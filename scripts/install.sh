#!/bin/bash

# =============================================================================
# 🔐 VAULTWARDEN INSTALLER (PORTABLE)
# =============================================================================
# Diseñado para una experiencia de usuario premium y configuración profesional.
# Usa Mise (mise-en-place) para gestionar herramientas de forma portable.
# Compatible con Alpine, Fedora, Ubuntu y cualquier distribución Linux.
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
    clear
    echo -e "${CYAN}"
    echo "    █░█ ▄▀█ █░█ █░░ ▀█▀ █░█ ▄▀█ █▀█ █▀▄ █▀▀ █▄░█"
    echo "    ▀▄▀ █▀█ █▄█ █▄▄ ░█░ ▀▄▀ █▀█ █▀▄ █▄▀ ██▄ █░▀█"
    echo -e "${NC}"
    echo -e "${BOLD}      BEYOND SECURITY — SELF-HOSTED STACK${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# --- FUNCIONES DE LOGGING ---
log_section() { echo -e "\n${BOLD}${MAGENTA}◈ $1${NC}\n" ; }
log_info()    { echo -e "  ${BLUE}ℹ${NC} $1" ; }
log_success() { echo -e "  ${GREEN}✔${NC} $1" ; }
log_warning() { echo -e "  ${YELLOW}⚠${NC} $1" ; }
log_error()   { echo -e "  ${RED}✖${NC} $1" ; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_SCRIPT="$SCRIPT_DIR/backup.sh"
CRON_SCHEDULE="${2:-0 3 * * *}"
UPDATE_SCRIPT="$SCRIPT_DIR/update.sh"
# Actualización semanal de Vaultwarden (domingo 4:00)
UPDATE_CRON_SCHEDULE="0 4 * * 0"

# Ubicaciones de clave AGE
AGE_KEY_LOCATIONS=(
    "${AGE_KEY_FILE:-}"
    "$PROJECT_DIR/.age-key"
    "$HOME/.age/vaultwarden.key"
    "/root/.age/vaultwarden.key"
)

# --- BUSCAR CLAVE AGE ---
find_age_key() {
    for key_path in "${AGE_KEY_LOCATIONS[@]}"; do
        if [[ -n "$key_path" && -f "$key_path" ]]; then
            echo "$key_path"
            return 0
        fi
    done
    return 1
}

# --- INSTALAR Y CONFIGURAR MISE ---
setup_mise() {
    log_section "ENTORNO PORTABLE (MISE)"

    # 1. Verificar si mise ya está disponible
    if command -v mise &> /dev/null; then
        log_success "Mise ya está instalado: $(mise --version)"
    else
        log_info "Mise no detectado. Instalando en modo usuario..."
        if command -v curl &> /dev/null; then
            curl -fsSL https://mise.run | sh
        elif command -v wget &> /dev/null; then
            wget -qO- https://mise.run | sh
        else
            log_error "Se necesita curl o wget para instalar Mise."
            exit 1
        fi

        # Asegurar que mise está en el PATH para esta sesión
        export PATH="$HOME/.local/bin:$PATH"

        if command -v mise &> /dev/null; then
            log_success "Mise instalado correctamente: $(mise --version)"
        else
            log_error "Fallo al instalar Mise. Verifica tu conexión."
            exit 1
        fi
    fi

    # 2. Instalar herramientas desde mise.toml
    log_info "Provisionando herramientas definidas en mise.toml..."
    cd "$PROJECT_DIR"

    if mise install --yes; then
        log_success "Todas las herramientas instaladas correctamente."
    else
        log_error "Fallo al instalar herramientas con Mise."
        exit 1
    fi

    # 3. Activar entorno para esta sesión
    eval "$(mise activate bash)"

    # 4. Verificar herramientas críticas
    echo ""
    log_info "Verificando herramientas provisionadas:"
    local tools=("age" "rclone" "sqlite3" "node" "bw")
    local all_ok=true
    for cmd in "${tools[@]}"; do
        if command -v "$cmd" &> /dev/null; then
            log_success "$cmd disponible"
        else
            log_warning "$cmd no encontrado (podría no ser necesario)"
            all_ok=false
        fi
    done

    echo ""
    if $all_ok; then
        log_success "Entorno portable listo. Todas las herramientas operativas."
    else
        log_warning "Algunas herramientas opcionales no están disponibles."
        log_info "El sistema puede funcionar sin ellas dependiendo de tu configuración."
    fi
}

# --- VERIFICAR DOCKER (única dependencia del sistema) ---
check_docker() {
    log_section "VERIFICANDO DOCKER"

    if command -v docker &> /dev/null; then
        log_success "Docker instalado: $(docker --version | head -1)"
    else
        log_error "Docker no está instalado."
        log_info "Instala Docker: ${CYAN}curl -fsSL https://get.docker.com | sh${NC}"
        exit 1
    fi

    if docker compose version &> /dev/null; then
        log_success "Docker Compose disponible."
    else
        log_warning "Docker Compose no encontrado. Se necesita para levantar el stack."
    fi
}

# --- CONFIGURAR ENTORNO (.env) ---
setup_env() {
    log_section "CONFIGURACIÓN DE ENTORNO"

    # 1. Verificar si existe .env plano
    if [[ -f "$PROJECT_DIR/.env" ]]; then
        log_success "Archivo de configuración (.env) detectado."
        return 0
    fi

    # 2. Verificar si existe .env.age y es descifrable
    if [[ -f "$PROJECT_DIR/.env.age" ]]; then
        local AGE_KEY
        AGE_KEY=$(find_age_key) || true

        if [[ -n "$AGE_KEY" ]]; then
            if age -d -i "$AGE_KEY" "$PROJECT_DIR/.env.age" > /dev/null 2>&1; then
                log_success "Archivo cifrado (.env.age) verificado correctamente."
                return 0
            else
                log_warning "Se detectó .env.age pero tu clave actual no puede descifrarlo."
                log_info "Esto es normal si acabas de clonar el repo."
            fi
        else
            log_warning "Se detectó .env.age pero no tienes ninguna clave para descifrarlo."
        fi
    else
        log_warning "No se encontró ningún archivo de configuración."
    fi

    # 3. Crear nuevo .env si no pasamos las validaciones anteriores
    read -p "    ¿Deseas inicializar una nueva configuración desde la plantilla? [S/n]: " -r response
    response=${response:-S}

    if [[ "$response" =~ ^[Ss]$ ]]; then
        cp "$PROJECT_DIR/.env.example" "$PROJECT_DIR/.env"
        log_success "Archivo .env creado exitosamente."
        log_info "No olvides editarlo con tus credenciales antes de cifrar."
    fi
}

# --- CONFIGURAR CRON ---
setup_cron() {
    local schedule="${1:-$CRON_SCHEDULE}"
    log_section "PROGRAMACIÓN DE BACKUPS"

    # Determinar ruta de log escribible
    local log_path="/var/log/vaultwarden_backup.log"
    if [[ ! -w "/var/log" ]]; then
        log_path="$PROJECT_DIR/backup.log"
        log_info "Usando log local: $log_path"
    fi

    # Validar formato básico de cron (5 campos)
    if [[ "$schedule" =~ ^[0-9]+[[:space:]]+[0-9]+$ ]]; then
        schedule="$schedule * * *"
    fi

    local CRON_CMD="$BACKUP_SCRIPT >> $log_path 2>&1"
    local CRON_ENTRY="$schedule $CRON_CMD"

    local CURRENT_CRON=""
    CURRENT_CRON=$(crontab -l 2>/dev/null | grep -v "$BACKUP_SCRIPT" || true)

    if crontab -l 2>/dev/null | grep -q "$BACKUP_SCRIPT"; then
        log_warning "Ya existe un backup programado."
        read -p "    ¿Deseas actualizar el horario? [s/N]: " -r response
        if [[ ! "$response" =~ ^[Ss]$ ]]; then
            log_info "Manteniendo cron actual."
            return 0
        fi
    fi

    if [[ -n "$CURRENT_CRON" ]]; then
        echo -e "${CURRENT_CRON}\n${CRON_ENTRY}" | crontab -
    else
        echo "$CRON_ENTRY" | crontab -
    fi

    log_success "Backup programado correctamente: ${BOLD}$schedule${NC}"
}

# --- CONFIGURAR CRON DE ACTUALIZACIÓN (VAULTWARDEN) ---
setup_cron_update() {
    local schedule="${1:-$UPDATE_CRON_SCHEDULE}"
    log_section "PROGRAMACIÓN DE ACTUALIZACIÓN DE VAULTWARDEN"

    local log_path="$PROJECT_DIR/update.log"
    if [[ -w "/var/log" ]]; then
        log_path="/var/log/vaultwarden_update.log"
    fi

    if [[ "$schedule" =~ ^[0-9]+[[:space:]]+[0-9]+$ ]]; then
        schedule="$schedule * * *"
    fi

    local CRON_CMD="$UPDATE_SCRIPT >> $log_path 2>&1"
    local CRON_ENTRY="$schedule $CRON_CMD"

    local CURRENT_CRON
    CURRENT_CRON=$(crontab -l 2>/dev/null | grep -v "$UPDATE_SCRIPT" || true)

    if crontab -l 2>/dev/null | grep -q "$UPDATE_SCRIPT"; then
        log_warning "Ya existe una actualización programada."
        read -p "    ¿Actualizar el horario? [s/N]: " -r response
        if [[ ! "$response" =~ ^[Ss]$ ]]; then
            log_info "Manteniendo cron actual."
            return 0
        fi
    fi

    if [[ -n "$CURRENT_CRON" ]]; then
        echo -e "${CURRENT_CRON}\n${CRON_ENTRY}" | crontab -
    else
        echo "$CRON_ENTRY" | crontab -
    fi

    log_success "Actualización de Vaultwarden programada: ${BOLD}$schedule${NC} (ver: $log_path)"
}

# --- MOSTRAR ESTADO ---
show_status() {
    log_section "SISTEMA DE SALUD"

    # Dependencias
    echo -e "  ${BOLD}Core Services (Mise):${NC}"
    for cmd in age rclone sqlite3 node bw docker; do
        if command -v "$cmd" &> /dev/null; then
            echo -e "    ${GREEN}●${NC} $cmd"
        else
            echo -e "    ${RED}○${NC} $cmd"
        fi
    done

    echo ""
    echo -e "  ${BOLD}Seguridad (AGE):${NC}"
    local AGE_KEY
    AGE_KEY=$(find_age_key) || true
    if [[ -n "$AGE_KEY" ]]; then
        log_success "Clave activa: $AGE_KEY"
    else
        log_error "Clave privada no encontrada"
    fi

    echo ""
    echo -e "  ${BOLD}Configuración:${NC}"
    for file in .env.age .env docker-compose.yml; do
        if [[ -f "$PROJECT_DIR/$file" ]]; then
            echo -e "    ${GREEN}●${NC} $file"
        else
            echo -e "    ${YELLOW}◌${NC} $file (vacío)"
        fi
    done

    echo ""
}

# --- INSTALACIÓN COMPLETA ---
full_install() {
    show_banner

    check_docker
    setup_mise

    log_section "CONFIGURACIÓN DE SEGURIDAD"
    if ! find_age_key > /dev/null; then
        log_warning "No se detectó una clave AGE."
        echo -e "    ${YELLOW}➔ Si eres usuario nuevo:${NC} Genera una nueva identidad."
        echo -e "    ${YELLOW}➔ Si estás restaurando:${NC} Cancela y copia tu backup a ${BOLD}~/.age/vaultwarden.key${NC}"
        echo ""
        read -p "    ¿Generar una nueva clave maestra ahora? (Responde 'n' para cancelar y restaurar manual) [S/n]: " -r response
        response=${response:-S}
        if [[ "$response" =~ ^[Ss]$ ]]; then
            "$SCRIPT_DIR/manage_secrets.sh" setup
        else
            log_info "Instalación pausada. Restaura tu clave y vuelve a ejecutar."
            exit 0
        fi
    else
        log_success "Clave de seguridad detectada correctamente."
    fi

    setup_env
    setup_cron "$CRON_SCHEDULE"
    setup_cron_update "$UPDATE_CRON_SCHEDULE"

    show_status

    log_section "FINALIZACIÓN"
    echo -e "  ${GREEN}${BOLD}✔ Entorno portable configurado con Mise.${NC}"
    echo -e "  ${BOLD}Sin dependencias del sistema operativo. Sin sudo.${NC}"
    echo ""
    echo -e "  ${BOLD}Pasos Finales:${NC}"
    echo -e "  1. Configura tus credenciales en el archivo ${CYAN}.env${NC}"
    echo -e "  2. Cifra tus secretos: ${CYAN}./scripts/manage_secrets.sh encrypt${NC}"
    echo -e "  3. Inicia el motor: ${CYAN}./scripts/start.sh${NC}"
    echo ""
    echo -e "  ${YELLOW}${BOLD}⚠ RECUERDA:${NC} Respalda tu clave AGE con ${CYAN}./scripts/manage_secrets.sh show-key${NC}"
    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# --- MAIN ---
case "${1:-}" in
    --deps)        check_docker && setup_mise ;;
    --cron)        setup_cron "${2:-$CRON_SCHEDULE}" ;;
    --cron-update) setup_cron_update "${2:-$UPDATE_CRON_SCHEDULE}" ;;
    --status)      show_status ;;
    --help|-h)
        echo "Uso: $0 [opción] [horario]"
        echo "  (sin args)       Instalación guiada (Mise + configuración)"
        echo "  --deps           Instalar/verificar herramientas (Docker + Mise)"
        echo "  --cron [horario] Configurar horario de backup (default: 0 3 * * *)"
        echo "  --cron-update [horario] Programar actualización de Vaultwarden (default: 0 4 * * 0 = domingo 4:00)"
        echo "  --status         Diagnóstico de salud"
        ;;
    "")       full_install ;;
    *)        echo "Opción inválida. Usa --help" ; exit 1 ;;
esac
