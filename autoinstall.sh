#!/bin/bash

# Salir inmediatamente si un comando falla
set -e

echo "========================================================"
echo "  Instalador Universal - Hrafnar Scraper Engine"
echo "========================================================"

# Función para ocultar logs y mostrar indicador de carga (spinner)
run_stage() {
    local message="$1"
    local command="$2"
    printf "%s " "$message"

    # Ejecuta el comando en segundo plano, silenciando stdout y stderr
    eval "$command" > /dev/null 2>&1 &
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

    # Espera a que termine y captura el código de salida
    wait $pid
    local exit_status=$?

    if [ $exit_status -ne 0 ]; then
        printf "\r%s [ERROR]    \n" "$message"
        echo "--> El comando falló silenciosamente."
        echo "--> Para debugear, ejecuta manualmente: $command"
        exit $exit_status
    else
        printf "\r%s [HECHO]    \n" "$message"
    fi
}

install_system_deps() {
    if [ -x "$(command -v apt-get)" ]; then
        run_stage "-> Actualizando repositorios APT..." "sudo apt-get update -y"
        run_stage "-> Instalando librerías gráficas (Xvfb, Chromium)..." "sudo apt-get install -y xvfb xauth libgbm-dev libnss3 libatk-bridge2.0-0 libxcomposite1 libxdamage1 libxrandr2 libpangocairo-1.0-0 libxss1 libgtk-3-0 curl git chromium-browser"
        run_stage "-> Configurando librerías de sonido..." "sudo apt-get install -y libasound2t64 || sudo apt-get install -y libasound2"
    elif [ -x "$(command -v dnf)" ]; then
        run_stage "-> Instalando dependencias en Fedora/RHEL (DNF)..." "sudo dnf install -y xorg-x11-server-Xvfb xauth mesa-libgbm nss at-spi2-atk libXcomposite libXdamage libXrandr alsa-lib pango libXScrnSaver gtk3 curl git chromium"
    elif [ -x "$(command -v pacman)" ]; then
        run_stage "-> Instalando dependencias en Arch Linux (Pacman)..." "sudo pacman -Sy --noconfirm xorg-server-xvfb xorg-xauth nss alsa-lib gtk3 libxss curl git chromium"
    else
        echo "Gestor de paquetes no soportado automáticamente para dependencias de interfaz. Instálalas manualmente."
    fi
}

install_node() {
    export NVM_DIR="$HOME/.nvm"

    if ! command -v node &> /dev/null; then
        run_stage "-> Instalando Node Version Manager (NVM)..." "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash"

        # Cargar nvm en la sesión actual
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

        run_stage "-> Descargando e instalando Node.js (LTS)..." "nvm install --lts && nvm use --lts && nvm alias default 'lts/*'"
    else
        echo "-> Node.js ya está instalado."
    fi

    # Nos aseguramos que nvm esté cargado para los siguientes pasos
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
}

fix_and_build_project() {
    if [ -f "package.json" ]; then
        run_stage "-> Configurando TypeScript (Convirtiendo AMD a CommonJS)..." "sed -i 's/\"module\": *\"[aA][mM][dD]\"/\"module\": \"commonjs\"/g' tsconfig*.json && sed -i '/\"outFile\":/d' tsconfig*.json"

        # Para NPM, nos aseguramos explícitamente de tener NVM cargado en el subshell
        run_stage "-> Descargando dependencias de NPM (esto puede tardar)..." "source \$HOME/.nvm/nvm.sh && npm install"

        run_stage "-> Compilando proyecto NestJS..." "source \$HOME/.nvm/n