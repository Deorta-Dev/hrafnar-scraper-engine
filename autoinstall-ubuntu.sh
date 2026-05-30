#!/usr/bin/env bash
# =============================================================================
#  HRAFNAR SCRAPER ENGINE — Auto-Installer
#  Compatibilidad: Ubuntu 24.04 LTS / Ubuntu 26.04 LTS
#  Autor: generado para Manuel De Orta Caraballo
# =============================================================================

set -euo pipefail

# ── Colores ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Configuración ────────────────────────────────────────────────────────────
NODE_VERSION="20"
APP_NAME="hrafnar"
APP_DIR="/opt/hrafnar"
SERVICE_NAME="hrafnar"
SERVICE_USER="hrafnar"
PORT="${PORT:-3000}"
DISPLAY_NUM="${DISPLAY_NUM:-99}"          # display virtual Xvfb
SOURCE_DIST="./dist"                      # ruta local al dist compilado

# ── Helpers ──────────────────────────────────────────────────────────────────
log()    { echo -e "${CYAN}[HRAFNAR]${NC} $*"; }
ok()     { echo -e "${GREEN}[  OK  ]${NC} $*"; }
warn()   { echo -e "${YELLOW}[ WARN ]${NC} $*"; }
error()  { echo -e "${RED}[ERROR ]${NC} $*"; exit 1; }
section(){ echo -e "\n${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; \
           echo -e "${BOLD}${CYAN}  $*${NC}"; \
           echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }

require_root() {
    [[ $EUID -eq 0 ]] || error "Este script debe ejecutarse como root: sudo bash $0"
}

detect_ubuntu() {
    local ver
    ver=$(lsb_release -rs 2>/dev/null || grep -oP '(?<=DISTRIB_RELEASE=)\S+' /etc/lsb-release 2>/dev/null || echo "unknown")
    case "$ver" in
        24.*) ok "Ubuntu $ver detectado — soportado." ;;
        26.*) ok "Ubuntu $ver detectado — soportado." ;;
        *)    warn "Ubuntu $ver — no verificado, continuando igualmente." ;;
    esac
}

check_dist_folder() {
    if [[ ! -d "$SOURCE_DIST" ]]; then
        error "No se encontró el directorio '$SOURCE_DIST'.\n\
  Asegúrate de haber ejecutado 'npm run build' antes de correr este instalador,\n\
  y que el script esté en la raíz del proyecto."
    fi
    ok "Directorio dist encontrado: $(realpath $SOURCE_DIST)"
}

# ── 1. Paquetes del sistema ───────────────────────────────────────────────────
install_system_deps() {
    section "1/8  Dependencias del sistema"

    log "Actualizando lista de paquetes..."
    apt-get update -qq

    log "Instalando dependencias base..."
    apt-get install -y --no-install-recommends \
        curl \
        wget \
        gnupg \
        ca-certificates \
        lsb-release \
        software-properties-common \
        apt-transport-https \
        git \
        unzip \
        build-essential \
        python3 \
        libssl-dev

    ok "Dependencias base instaladas."
}

# ── 2. Node.js 20 ────────────────────────────────────────────────────────────
install_node() {
    section "2/8  Node.js $NODE_VERSION"

    if command -v node &>/dev/null; then
        local current
        current=$(node -v | grep -oP '\d+' | head -1)
        if [[ "$current" -ge "$NODE_VERSION" ]]; then
            ok "Node.js $(node -v) ya está instalado — se omite."
            return
        fi
        warn "Node.js $(node -v) encontrado pero se requiere v$NODE_VERSION+. Actualizando..."
    fi

    log "Descargando NodeSource setup para Node $NODE_VERSION..."
    curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION}.x" | bash -

    apt-get install -y nodejs
    ok "Node.js $(node -v) instalado. npm $(npm -v)."
}

# ── 3. Dependencias de Chromium / Playwright en el sistema ───────────────────
install_chromium_deps() {
    section "3/8  Dependencias de Chromium (librerías del sistema)"

    log "Instalando librerías necesarias para Chromium headful..."
    apt-get install -y --no-install-recommends \
        libnss3 \
        libatk1.0-0 \
        libatk-bridge2.0-0 \
        libcups2 \
        libxcomposite1 \
        libxdamage1 \
        libxfixes3 \
        libxrandr2 \
        libgbm1 \
        libdrm2 \
        libasound2t64 \
        libpangocairo-1.0-0 \
        libpango-1.0-0 \
        libcairo2 \
        libatspi2.0-0 \
        libgtk-3-0 \
        libx11-xcb1 \
        libxcb-dri3-0 \
        libxshmfence1 \
        fonts-liberation \
        libappindicator3-1 \
        xdg-utils \
        libvulkan1 \
        libgles2

    ok "Librerías de Chromium instaladas."
}

# ── 4. Xvfb (display virtual) ────────────────────────────────────────────────
install_xvfb() {
    section "4/8  Xvfb — Display virtual para headless:false"

    log "Instalando Xvfb y herramientas de X11..."
    apt-get install -y --no-install-recommends \
        xvfb \
        x11-utils \
        xauth

    ok "Xvfb instalado."
}

# ── 5. Usuario del sistema y directorio de instalación ───────────────────────
setup_user_and_dir() {
    section "5/8  Usuario de sistema y directorio $APP_DIR"

    if ! id "$SERVICE_USER" &>/dev/null; then
        log "Creando usuario de sistema '$SERVICE_USER'..."
        useradd --system \
                --shell /usr/sbin/nologin \
                --home-dir "$APP_DIR" \
                --no-create-home \
                "$SERVICE_USER"
        ok "Usuario '$SERVICE_USER' creado."
    else
        ok "Usuario '$SERVICE_USER' ya existe."
    fi

    log "Creando directorio $APP_DIR..."
    mkdir -p "$APP_DIR"

    log "Copiando contenido de ./dist a $APP_DIR..."
    rsync -a --delete "${SOURCE_DIST}/" "${APP_DIR}/"
    ok "Archivos copiados."
}

# ── 6. npm install en producción + Playwright Chromium ───────────────────────
install_app_deps() {
    section "6/8  npm install + Playwright Chromium"

    log "Ejecutando npm install en $APP_DIR..."
    cd "$APP_DIR"
    npm install --omit=dev --force
    ok "Dependencias de producción instaladas."

    log "Instalando Chromium vía Playwright..."
    # Playwright necesita la variable HOME para saber dónde guardar el navegador
    PLAYWRIGHT_BROWSERS_PATH="/opt/playwright-browsers" \
    HOME="/root" \
    npx playwright install chromium

    # Guardar la ruta del navegador para usarla en el servicio
    CHROMIUM_EXECUTABLE=$(PLAYWRIGHT_BROWSERS_PATH="/opt/playwright-browsers" npx playwright show-browsers 2>/dev/null | grep -oP '/opt/playwright-browsers/\S+/chrome' | head -1 || true)

    ok "Chromium de Playwright instalado en /opt/playwright-browsers."

    # Permisos del directorio de la app
    chown -R "${SERVICE_USER}:${SERVICE_USER}" "$APP_DIR"
    chown -R "${SERVICE_USER}:${SERVICE_USER}" "/opt/playwright-browsers" 2>/dev/null || true
}

# ── 7. Servicio systemd ───────────────────────────────────────────────────────
create_systemd_service() {
    section "7/8  Servicio systemd: $SERVICE_NAME"

    local xvfb_socket="/tmp/.X${DISPLAY_NUM}-lock"

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
Documentation=https://github.com/tu-repo/hrafnar
After=network.target ${SERVICE_NAME}-display.service
Requires=${SERVICE_NAME}-display.service

[Service]
Type=simple
User=${SERVICE_USER}
Group=${SERVICE_USER}
WorkingDirectory=${APP_DIR}

# Variables de entorno
Environment=NODE_ENV=production
Environment=PORT=${PORT}
Environment=DISPLAY=:${DISPLAY_NUM}
Environment=PLAYWRIGHT_BROWSERS_PATH=/opt/playwright-browsers
Environment=HOME=${APP_DIR}

# Asegurar que el display esté listo antes de iniciar
ExecStartPre=/bin/sleep 2

# Comando principal
ExecStart=/usr/bin/node ${APP_DIR}/main.js

# Reinicio automático
Restart=on-failure
RestartSec=5
StartLimitIntervalSec=60
StartLimitBurst=5

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SERVICE_NAME}

# Seguridad básica
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

    log "Recargando systemd..."
    systemctl daemon-reload

    log "Habilitando servicios para inicio automático..."
    systemctl enable "${SERVICE_NAME}-display.service"
    systemctl enable "${SERVICE_NAME}.service"

    ok "Servicios systemd creados y habilitados."
}

# ── 8. Arrancar servicios ────────────────────────────────────────────────────
start_services() {
    section "8/8  Iniciando servicios"

    log "Iniciando display virtual Xvfb..."
    systemctl restart "${SERVICE_NAME}-display.service"
    sleep 2

    log "Iniciando Hrafnar Scraper Engine..."
    systemctl restart "${SERVICE_NAME}.service"
    sleep 3

    # Verificación de estado
    if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
        ok "✅ Hrafnar está corriendo."
    else
        warn "El servicio no arrancó correctamente. Mostrando últimas líneas del log:"
        journalctl -u "${SERVICE_NAME}.service" --no-pager -n 30
        error "Revisa los logs con: journalctl -u ${SERVICE_NAME} -f"
    fi
}

# ── Resumen final ─────────────────────────────────────────────────────────────
print_summary() {
    echo ""
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║       HRAFNAR SCRAPER ENGINE — INSTALADO ✅          ║${NC}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BOLD}Directorio de la app:${NC}   $APP_DIR"
    echo -e "  ${BOLD}Puerto:${NC}                 $PORT"
    echo -e "  ${BOLD}Display virtual:${NC}        :${DISPLAY_NUM}"
    echo -e "  ${BOLD}Usuario de servicio:${NC}    $SERVICE_USER"
    echo -e "  ${BOLD}Navegadores:${NC}            /opt/playwright-browsers"
    echo ""
    echo -e "  ${BOLD}${CYAN}Comandos útiles:${NC}"
    echo -e "    ${YELLOW}systemctl status ${SERVICE_NAME}${NC}           — estado del servicio"
    echo -e "    ${YELLOW}journalctl -u ${SERVICE_NAME} -f${NC}           — logs en tiempo real"
    echo -e "    ${YELLOW}systemctl restart ${SERVICE_NAME}${NC}          — reiniciar"
    echo -e "    ${YELLOW}systemctl stop ${SERVICE_NAME}${NC}             — detener"
    echo ""
    echo -e "  ${BOLD}API disponible en:${NC}      http://localhost:${PORT}"
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
    echo -e "  Ubuntu 24.04 / 26.04 · NestJS + Playwright\n"

    require_root
    detect_ubuntu
    check_dist_folder

    install_system_deps
    install_node
    install_chromium_deps
    install_xvfb
    setup_user_and_dir
    install_app_deps
    create_systemd_service
    start_services
    print_summary
}

main "$@"