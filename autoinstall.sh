#!/bin/bash

# Salir inmediatamente si un comando falla
set -e

echo "========================================================"
echo "  Instalador Universal - Hrafnar Scraper Engine"
echo "========================================================"

# Pedir la contraseña de sudo ahora para que los procesos en segundo plano no se congelen
echo "Por favor, introduce tu contraseña si el sistema lo requiere:"
sudo -v

# Función para ocultar logs y mostrar indicador, PERO mostrar el error si falla
run_stage() {
    local message="$1"
    local command="$2"
    printf "%s " "$message"

    # Creamos un archivo temporal para guardar los logs de este comando
    local tmp_log=$(mktemp)

    # Ejecuta el comando en segundo plano, guardando salida y errores
    eval "$command" > "$tmp_log" 2>&1 &
    local pid=$!

    # Spinner animado
    local delay=0.1
    local spinstr='|/-\'
    while kill -0 $pid 2>/dev/null; do
        local temp=${spinstr#?}
        printf "[%c]" "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b"
    done

    # === LA SOLUCIÓN ===
    # Apagamos set -e temporalmente para que 'wait' no aborte el script si hay un error
    set +e
    wait $pid
    local exit_status=$?
    set -e
    # ===================

    if [ $exit_status -ne 0 ]; then
        printf "\r%s [ERROR]    \n" "$message"
        echo -e "\n==================== DETALLE DEL ERROR ===================="
        cat "$tmp_log" # <-- AHORA SÍ SE MOSTRARÁ
        echo "==========================================================="
        echo "--> Comando que falló: $command"
        rm -f "$tmp_log"
        exit $exit_status
    else
        printf "\r%s [HECHO]    \n" "$message"
        rm -f "$tmp_log"
    fi
}

install_system_deps() {
    if [ -x "$(command -v apt-get)" ]; then
        run_stage "-> Actualizando repositorios APT..." "sudo apt-get update -y"
        run_stage "-> Instalando librerías gráficas (Xvfb, Chromium)..." "sudo apt-get install -y xvfb xauth libgbm-dev libnss3 libatk-bridge2.0-0 libxcomposite1 libxdamage1 libxrandr2 libpangocairo-1.0-0 libxss1 libgtk-3-0 curl git chromium-browser"
        run_stage "-> Configurando librerías de sonido..." "sudo apt-get install -y libasound2t64 || sudo apt-get install -y libasound2"
    elif [ -x "$(command -v dnf)" ]; then
        run_stage "-> Instalando dependencias en Fedora/RHEL (DNF)..." "sudo dnf install -y xorg-x11-server-Xvfb xauth mesa-libgbm nss at-spi2-atk libXcomposite libXdamage libXrandr alsa-lib pango libXScrnSaver gtk3 curl git chromium"
    else
        echo "Gestor de paquetes no soportado automáticamente. Instálalas manualmente."
    fi
}

install_node() {
    export NVM_DIR="$HOME/.nvm"

    if ! command -v node &> /dev/null; then
        run_stage "-> Instalando Node Version Manager (NVM)..." "curl -o- https://raw