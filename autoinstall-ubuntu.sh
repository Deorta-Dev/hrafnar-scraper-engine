#!/usr/bin/env bash
# =============================================================================
#  HRAFNAR SCRAPER ENGINE — Auto-Installer
#  Compatibilidad: Ubuntu 24.04 LTS / Ubuntu 26.04 LTS
#  Autor: generado para Manuel De Orta Caraballo
# =============================================================================

set -euo pipefail

# ── Colores ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── Configuración ─────────────────────────────────────────────────────────────
NODE_VERSION="20"
APP_DIR="/opt/hrafnar"
SERVICE_NAME="hrafnar"
SERVICE_USER="hrafnar"
PORT="${PORT:-3000}"
DISPLAY_NUM="${DISPLAY_NUM:-99}"
SOURCE_DIST="./dist"

# Log temporal: todos los comandos ruidosos escriben aquí
LOG_FILE="/tmp/hrafnar-install.log"
> "$LOG_FILE"

# ── Helpers ───────────────────────────────────────────────────────────────────

# Imprime una línea de progreso con spinner animado mientras corre un comando.
# Uso: run "Descripción" comando [args...]
# Si el comando falla, vuelca el log y sale.
run() {
    local desc="$1"; shift
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0

    # Ejecutar en background, redirigir salida al log
    ("$@" >> "$LOG_FILE" 2>&1) &
    local pid=$!

    # Spinner mientras el proceso corre
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${CYAN}${frames[$i]}${NC}  ${DIM}%s...${NC}" "$desc"
        i=$(( (i+1) % ${#frames[@]} ))
        sleep 0.1
    done

    # Capturar exit code
    wait "$pid"
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        printf "\r  ${GREEN}✔${NC}  %s\n" "$desc"
    else
        printf "\r  ${RED}✘${NC}  %s\n" "$desc"
        echo ""
        echo -e "${RED}${BOLD}── Error en: $desc ─────────────────────────────────${NC}"
        cat "$LOG_FILE"
        echo -e "${RED}${BOLD}────────────────────────────────────────────────────${NC}"
        echo -e "${DIM}Log completo en: $LOG_FILE${NC}"
        exit 1
    fi
}

# run_ok: igual que run pero no muere si falla (para pasos opcionales)
run_ok() {
    local desc="$1"; shift
    run "$desc" "$@" || true
}

step()  { echo -e "\n${BOLD}  $*${NC}"; }
warn()  { echo -e "  ${YELLOW}⚠${NC}  $*"; }
info()  { echo -e "  ${DIM}ℹ  $*${NC}"; }
fatal() { echo -e "\n  ${RED}${BOLD}✘  $*${NC}\n"; exit 1; }

# ── Variables globales ────────────────────────────────────────────────────────
UBUNTU_VER=""
PLAYWRIGHT_UBUNTU_COMPAT=""

# ── Preflight ─────────────────────────────────────────────────────────────────
require_root() {
    [[ $EUID -eq 0 ]] || fatal "Ejecuta con root: sudo bash $0"
}

detect_ubuntu() {
    UBUNTU_VER=$(lsb_release -rs 2>/dev/null \
        || grep -oP '(?<=DISTRIB_RELEASE=)\S+' /etc/lsb-release 2>/dev/null \
        || echo "unknown")
    case "$UBUNTU_VER" in
        24.*) info "Ubuntu $UBUNTU_VER — soporte nativo." ;;
        26.*)
            info "Ubuntu $UBUNTU_VER — aplicando workaround Playwright."
            export PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS=1
            PLAYWRIGHT_UBUNTU_COMPAT="24.04"
            ;;
        *)    warn "Ubuntu $UBUNTU_VER — no verificado, continuando." ;;
    esac
}

check_dist_folder() {
    [[ -d "$SOURCE_DIST" ]] \
        || fatal "No se encontró '$SOURCE_DIST'.\nEjecuta 'npm run build' antes de correr el instalador."
}

# ── Pasos silenciosos ─────────────────────────────────────────────────────────

do_apt_update() {
    apt-get update -qq
}

do_system_deps() {
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
        curl wget gnupg ca-certificates lsb-release \
        software-properties-common apt-transport-https \
        git unzip build-essential python3 libssl-dev rsync
}

do_node() {
    if command -v node &>/dev/null; then
        local current
        current=$(node -v | grep -oP '\d+' | head -1)
        if [[ "$current" -ge "$NODE_VERSION" ]]; then
            return 0
        fi
    fi
    curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION}.x" | bash - >> "$LOG_FILE" 2>&1
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nodejs
}

do_chromium_deps() {
    local DEPS=(
        libnss3 libatk-bridge2.0-0 libcups2
        libxcomposite1 libxdamage1 libxfixes3 libxrandr2
        libgbm1 libdrm2 libpangocairo-1.0-0 libpango-1.0-0
        libcairo2 libatspi2.0-0 libx11-xcb1 libxcb-dri3-0
        libxshmfence1 fonts-liberation xdg-utils libvulkan1 libgles2
    )
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends "${DEPS[@]}"

    # Paquetes con nombre diferente según versión de Ubuntu
    for pkg in libatk1.0-0 libatk1.0-0t64; do
        apt-cache show "$pkg" &>/dev/null && \
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends "$pkg" && break
    done
    for pkg in libasound2t64 libasound2; do
        apt-cache show "$pkg" &>/dev/null && \
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends "$pkg" && break
    done
    for pkg in libgtk-3-0 libgtk-3-0t64; do
        apt-cache show "$pkg" &>/dev/null && \
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends "$pkg" && break
    done
    apt-cache show libappindicator3-1 &>/dev/null && \
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends libappindicator3-1 || true
}

do_xvfb() {
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
        xvfb x11-utils xauth
}

do_user_and_dir() {
    if ! id "$SERVICE_USER" &>/dev/null; then
        useradd --system --shell /usr/sbin/nologin \
                --home-dir "$APP_DIR" --no-create-home "$SERVICE_USER"
    fi
    mkdir -p "$APP_DIR"
    rsync -a --delete "${SOURCE_DIST}/" "${APP_DIR}/"
}

do_npm_install() {
    cd "$APP_DIR"
    npm install --omit=dev --force
}

do_playwright_install() {
    cd "$APP_DIR"
    if [[ "$PLAYWRIGHT_UBUNTU_COMPAT" == "24.04" ]]; then
        cp /etc/os-release /etc/os-release.bak
        [[ -f /etc/lsb-release ]] && cp /etc/lsb-release /etc/lsb-release.bak

        cat > /etc/os-release <<'OSEOF'
NAME="Ubuntu"
VERSION="24.04.2 LTS (Noble Numbat)"
ID=ubuntu
ID_LIKE=debian
PRETTY_NAME="Ubuntu 24.04.2 LTS"
VERSION_ID="24.04"
UBUNTU_CODENAME=noble
OSEOF
        cat > /etc/lsb-release <<'LSBEOF'
DISTRIB_ID=Ubuntu
DISTRIB_RELEASE=24.04
DISTRIB_CODENAME=noble
DISTRIB_DESCRIPTION="Ubuntu 24.04.2 LTS"
LSBEOF

        local pw_exit=0
        PLAYWRIGHT_BROWSERS_PATH="/opt/playwright-browsers" \
        PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS=1 \
        HOME="/root" \
        npx playwright install chromium >> "$LOG_FILE" 2>&1 || pw_exit=$?

        mv /etc/os-release.bak /etc/os-release
        [[ -f /etc/lsb-release.bak ]] && mv /etc/lsb-release.bak /etc/lsb-release

        [[ $pw_exit -ne 0 ]] && return $pw_exit
    else
        PLAYWRIGHT_BROWSERS_PATH="/opt/playwright-browsers" \
        HOME="/root" \
        npx playwright install chromium >> "$LOG_FILE" 2>&1
    fi

    chown -R "${SERVICE_USER}:${SERVICE_USER}" "$APP_DIR"
    chown -R "${SERVICE_USER}:${SERVICE_USER}" "/opt/playwright-browsers" 2>/dev/null || true
}

do_systemd() {
    cat > "/etc/systemd/system/${SERVICE_NAME}-display.service" <<EOF
[Unit]
Description=Hrafnar Virtual Display (Xvfb)
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/Xvfb :${DISPLAY_NUM} -screen 0 1920x1080x24 -ac +extension GLX +render -noreset
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=Hrafnar Scraper Engine (NestJS + Playwright)
After=network.target ${SERVICE_NAME}-display.service
Requires=${SERVICE_NAME}-display.service

[Service]
Type=simple
User=${SERVICE_USER}
Group=${SERVICE_USER}
WorkingDirectory=${APP_DIR}
Environment=NODE_ENV=production
Environment=PORT=${PORT}
Environment=DISPLAY=:${DISPLAY_NUM}
Environment=PLAYWRIGHT_BROWSERS_PATH=/opt/playwright-browsers
Environment=HOME=${APP_DIR}
ExecStartPre=/bin/sleep 2
ExecStart=/usr/bin/node ${APP_DIR}/main.js
Restart=on-failure
RestartSec=5
StartLimitIntervalSec=60
StartLimitBurst=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SERVICE_NAME}
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload >> "$LOG_FILE" 2>&1
    systemctl enable "${SERVICE_NAME}-display.service" >> "$LOG_FILE" 2>&1
    systemctl enable "${SERVICE_NAME}.service" >> "$LOG_FILE" 2>&1
}

do_start_services() {
    systemctl restart "${SERVICE_NAME}-display.service" >> "$LOG_FILE" 2>&1
    sleep 2
    systemctl restart "${SERVICE_NAME}.service" >> "$LOG_FILE" 2>&1
    sleep 3
    systemctl is-active --quiet "${SERVICE_NAME}.service"
}

# ── Resumen final ─────────────────────────────────────────────────────────────
print_summary() {
    echo ""
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║       HRAFNAR SCRAPER ENGINE — INSTALADO  ✅         ║${NC}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BOLD}Directorio:${NC}     $APP_DIR"
    echo -e "  ${BOLD}Puerto:${NC}         $PORT"
    echo -e "  ${BOLD}Display:${NC}        :${DISPLAY_NUM}"
    echo -e "  ${BOLD}Usuario:${NC}        $SERVICE_USER"
    echo -e "  ${BOLD}Navegadores:${NC}    /opt/playwright-browsers"
    echo ""
    echo -e "  ${BOLD}${CYAN}Comandos útiles:${NC}"
    echo -e "  ${YELLOW}  systemctl status ${SERVICE_NAME}${NC}       — estado"
    echo -e "  ${YELLOW}  journalctl -u ${SERVICE_NAME} -f${NC}       — logs en vivo"
    echo -e "  ${YELLOW}  systemctl restart ${SERVICE_NAME}${NC}      — reiniciar"
    echo -e "  ${YELLOW}  systemctl stop ${SERVICE_NAME}${NC}         — detener"
    echo ""
    echo -e "  ${BOLD}API:${NC}  http://localhost:${PORT}"
    echo ""
}

# ══════════════════════════════════════════════════════════════════════════════
#  MAIN
# ══════════════════════════════════════════════════════════════════════════════
main() {
    clear
    echo -e "${BOLD}${CYAN}"
    echo "  ██╗  ██╗██████╗  █████╗ ███████╗███╗   ██╗ █████╗ ██████╗ "
    echo "  ██║  ██║██╔══██╗██╔══██╗██╔════╝████╗  ██║██╔══██╗██╔══██╗"
    echo "  ███████║██████╔╝███████║█████╗  ██╔██╗ ██║███████║██████╔╝"
    echo "  ██╔══██║██╔══██╗██╔══██║██╔══╝  ██║╚██╗██║██╔══██║██╔══██╗"
    echo "  ██║  ██║██║  ██║██║  ██║██║     ██║ ╚████║██║  ██║██║  ██║"
    echo "  ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝  ╚═╝"
    echo -e "${NC}"
    echo -e "  ${BOLD}Scraper Engine — Instalador automático${NC}"
    echo -e "  ${DIM}Ubuntu 24.04 / 26.04 · NestJS + Playwright${NC}\n"

    require_root
    detect_ubuntu
    check_dist_folder

    step "Sistema"
    run  "Actualizando paquetes"                do_apt_update
    run  "Instalando dependencias base"         do_system_deps

    step "Node.js $NODE_VERSION"
    run  "Instalando Node.js $NODE_VERSION"     do_node

    step "Chromium"
    run  "Instalando librerías del sistema"     do_chromium_deps
    run  "Instalando Xvfb (display virtual)"   do_xvfb

    step "Aplicación"
    run  "Copiando archivos a $APP_DIR"         do_user_and_dir
    run  "npm install (producción)"             do_npm_install
    run  "Instalando Chromium (Playwright)"     do_playwright_install

    step "Servicio"
    run  "Creando unidades systemd"             do_systemd
    run  "Iniciando servicios"                  do_start_services

    print_summary
}

main "$@"