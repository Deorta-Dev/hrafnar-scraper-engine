#!/bin/bash

# Salir inmediatamente si un comando falla
set -e

echo "========================================================"
echo "  Instalador Universal - Hrafnar Scraper Engine"
echo "========================================================"

# Función para ocultar logs y mostrar indicador, PERO mostrar el error si falla
run_stage() {
    local message="$1"
    local command="$2"
    printf "%s " "$message"

    # Creamos un archivo temporal para guardar los logs de este comando
    local tmp_log=$(mktemp)

    # Ejecuta el comando en segundo plano, guardando salida y errores en el archivo temporal
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

    # Espera a que termine y captura el código de salida
    wait $pid
    local exit_status=$?

    if [ $exit_status -ne 0 ]; then
        printf "\r%s [ERROR]    \n" "$message"
        echo -e "\n==================== DETALLE DEL ERROR ===================="
        cat "$tmp_log" # <-- AQUI MOSTRAMOS EL ERROR COMPLETO
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
        echo "Gestor de paquetes no soportado automáticamente para dependencias de interfaz. Instálalas manualmente."
    fi
}

install_node() {
    export NVM_DIR="$HOME/.nvm"

    if ! command -v node &> /dev/null; then
        run_stage "-> Instalando Node Version Manager (NVM)..." "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        run_stage "-> Descargando e instalando Node.js (LTS)..." "nvm install --lts && nvm use --lts && nvm alias default 'lts/*'"
    else
        echo "-> Node.js ya está instalado."
    fi

    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
}

fix_and_build_project() {
    if [ -f "package.json" ]; then
        run_stage "-> Configurando TypeScript (AMD a CommonJS)..." "sed -i 's/\"module\": *\"[aA][mM][dD]\"/\"module\": \"commonjs\"/g' tsconfig*.json && sed -i '/\"outFile\":/d' tsconfig*.json"
        run_stage "-> Descargando dependencias de NPM (esto puede tardar)..." "source \$HOME/.nvm/nvm.sh && npm install"
        run_stage "-> Compilando proyecto NestJS..." "source \$HOME/.nvm/nvm.sh && npm run build"
    else
        echo "ADVERTENCIA: No se encontró package.json. Ejecuta este script desde la raíz del proyecto."
        exit 1
    fi
}

deploy_to_opt() {
    run_stage "-> Limpiando instalación previa..." "sudo rm -rf /opt/hrafnar"
    run_stage "-> Creando directorio de sistema /opt/hrafnar..." "sudo mkdir -p /opt/hrafnar"

    if [ -d "./dist" ]; then
        run_stage "-> Copiando código de producción (dist)..." "sudo bash -c 'cp -r dist/* /opt/hrafnar/'"
    else
        echo "ERROR: La carpeta dist no se generó en el proceso de build."
        exit 1
    fi

    run_stage "-> Configurando dependencias en producción..." "sudo cp package.json /opt/hrafnar/ && sudo cp -r node_modules /opt/hrafnar/"

    CURRENT_USER=$(whoami)
    run_stage "-> Asignando permisos finales..." "sudo chown -R $CURRENT_USER:$CURRENT_USER /opt/hrafnar"
}

setup_systemd_service() {
    SERVICE_NAME="hrafnar"
    SERVICE_FILE="/tmp/${SERVICE_NAME}.service"
    CURRENT_USER=$(whoami)
    XVFB_PATH=$(which xvfb-run)
    NODE_PATH=$(which node)

    # Bloque de Systemd fuera de run_stage para evitar errores de sintaxis "Unterminated quoted string"
    printf "-> Generando archivo de servicio de Systemd... "
    cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Hrafnar Scraper Engine con Xvfb
After=network.target

[Service]
Type=simple
User=$CURRENT_USER
WorkingDirectory=/opt/hrafnar
Environment=NODE_ENV=production
Environment=PATH=$PATH
ExecStart=$XVFB_PATH --auto-servernum --server-args="-screen 0 1280x1024x24" $NODE_PATH /opt/hrafnar/main.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    printf "[HECHO]\n"

    run_stage "-> Registrando hrafnar.service en el sistema..." "sudo mv $SERVICE_FILE /etc/systemd/system/${SERVICE_NAME}.service && sudo systemctl daemon-reload"
    run_stage "-> Inicializando servicio en segundo plano..." "sudo systemctl enable ${SERVICE_NAME}.service && sudo systemctl restart ${SERVICE_NAME}.service"
}

# Flujo de ejecución
install_system_deps
install_node
fix_and_build_project
deploy_to_opt
setup_systemd_service

echo "========================================================"
echo "  ¡Instalación completada con éxito!"
echo "========================================================"
echo "El motor scraper se está ejecutando desde /opt/hrafnar"
echo "Para ver los logs en tiempo real, ejecuta:"
echo "  sudo journalctl -u hrafnar -f"
echo "========================================================"