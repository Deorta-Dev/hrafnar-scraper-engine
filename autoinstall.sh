#!/bin/bash

# Salir inmediatamente si un comando falla
set -e

echo "========================================================"
echo "  Instalador Universal - Scraper Engine (Playwright + Xvfb)"
echo "========================================================"

# Función para detectar el gestor de paquetes e instalar dependencias del sistema
install_system_deps() {
    echo "Detectando sistema operativo y gestor de paquetes..."
    if [ -x "$(command -v apt-get)" ]; then
        echo "-> Sistema basado en Debian/Ubuntu detectado (APT)."
        sudo apt-get update
        # Instalar dependencias de Xvfb, librerías gráficas y Chromium
        sudo apt-get install -y xvfb xauth libgbm-dev libnss3 libatk-bridge2.0-0 libxcomposite1 libxdamage1 libxrandr2 libpangocairo-1.0-0 libxss1 libgtk-3-0 curl git chromium-browser
        sudo apt-get install -y libasound2t64 || sudo apt-get install -y libasound2
    elif [ -x "$(command -v dnf)" ]; then
        echo "-> Sistema basado en Fedora/RHEL/CentOS detectado (DNF)."
        sudo dnf install -y xorg-x11-server-Xvfb xauth mesa-libgbm nss at-spi2-atk libXcomposite libXdamage libXrandr alsa-lib pango libXScrnSaver gtk3 curl git chromium
    elif [ -x "$(command -v pacman)" ]; then
        echo "-> Sistema basado en Arch Linux detectado (Pacman)."
        sudo pacman -Sy --noconfirm xorg-server-xvfb xorg-xauth nss alsa-lib gtk3 libxss curl git chromium
    else
        echo "Gestor de paquetes no soportado automáticamente para dependencias de interfaz. Instálalas manualmente."
    fi
    echo "Dependencias del sistema instaladas."
}

# Función para instalar Node.js usando NVM
install_node() {
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    if ! command -v node &> /dev/null; then
        echo "Instalando NVM y Node.js (LTS)..."
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        nvm install --lts
        nvm use --lts
        nvm alias default 'lts/*'
    fi
    echo "Node.js instalado: $(node -v)"
}

# Función para configurar el proyecto
setup_project() {
    if [ -f "package.json" ]; then
        echo "Instalando dependencias del proyecto (incluyendo playwright-core)..."
        npm install

        echo "Ejecutando build personalizado (nest build && node simplify-pkg.js)..."
        npm run build

        if [ -d "./dist" ]; then
            echo "Proyecto compilado correctamente. Carpeta ./dist generada."
        else
            echo "ADVERTENCIA: La carpeta ./dist no se generó. Revisa tu proceso de build."
        fi
    else
        echo "ADVERTENCIA: No se encontró package.json. Ejecuta este script desde la raíz del proyecto."
        exit 1
    fi
}

# Función para crear e iniciar el servicio en Systemd
setup_systemd_service() {
    echo "Configurando el servicio de Systemd..."

    SERVICE_NAME="hrafnar"
    SERVICE_FILE="/tmp/${SERVICE_NAME}.service"
    CURRENT_USER=$(whoami)
    CURRENT_DIR=$(pwd)
    XVFB_PATH=$(which xvfb-run)

    # Obtenemos la ruta absoluta de node (usando nvm o el del sistema)
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    NODE_PATH=$(which node)

    # Crear el archivo de servicio apuntando directamente a la carpeta ./dist
    cat <<EOF > $SERVICE_FILE
[Unit]
Description=Scraper Engine con Xvfb (Playwright Headless False)
After=network.target

[Service]
Type=simple
User=$CURRENT_USER
WorkingDirectory=$CURRENT_DIR
Environment=NODE_ENV=production
Environment=PATH=$PATH
# Ejecutamos Node.js apuntando directamente al archivo en ./dist envuelto en xvfb-run
ExecStart=$XVFB_PATH --auto-servernum --server-args="-screen 0 1280x1024x24" $NODE_PATH $CURRENT_DIR/dist/main
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    # Mover el archivo al directorio de systemd usando sudo
    sudo mv $SERVICE_FILE /etc/systemd/system/${SERVICE_NAME}.service

    # Recargar systemd, habilitar e iniciar el servicio
    sudo systemctl daemon-reload
    sudo systemctl enable ${SERVICE_NAME}.service
    sudo systemctl restart ${SERVICE_NAME}.service

    echo "Servicio '${SERVICE_NAME}' configurado apuntando a ./dist/main."
}

# Ejecución
install_system_deps
install_node
setup_project
setup_systemd_service

echo "========================================================"
echo "  ¡Instalación completada con éxito!"
echo "========================================================"
echo "Para ver los logs en tiempo real, ejecuta:"
echo "  sudo journalctl -u hrafnar -f"
echo "========================================================"