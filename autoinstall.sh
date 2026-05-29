#!/bin/bash

# Script de instalación para Hrafnar Scraper Engine
# Ejecutar con: sudo bash autoinstall.sh

echo "========================================================"
echo "  Instalador Universal - Hrafnar Scraper Engine"
echo "========================================================"

# Función para ocultar logs y mostrar indicador de trabajo
run_stage() {
    local message="$1"
    local command="$2"
    printf "%s " "$message"
    local tmp_log=$(mktemp)
    eval "$command" > "$tmp_log" 2>&1 &
    local pid=$!
    local spinstr='|/-\'
    while kill -0 $pid 2>/dev/null; do
        local temp=${spinstr#?}
        printf "[%c]" "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep 0.1
        printf "\b\b\b"
    done
    wait $pid
    local exit_status=$?
    if [ $exit_status -ne 0 ]; then
        printf "\r%s [ERROR]    \n" "$message"
        cat "$tmp_log"
        rm -f "$tmp_log"
        exit $exit_status
    else
        printf "\r%s [HECHO]    \n" "$message"
        rm -f "$tmp_log"
    fi
}

# 1. Dependencias del sistema
run_stage "-> Instalando librerías base..." "apt-get update -y && apt-get install -y xvfb xauth libgbm-dev libnss3 libatk-bridge2.0-0 libxcomposite1 libxdamage1 libxrandr2 libpangocairo-1.0-0 libxss1 libgtk-3-0 curl git chromium-browser libasound2t64"

# 2. Node.js
if ! command -v node &> /dev/null; then
    run_stage "-> Instalando Node.js..." "curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - && apt-get install -y nodejs"
fi

# 3. Build del proyecto
if [ -f "package.json" ]; then
    run_stage "-> Configurando TypeScript..." "sed -i 's/\"module\": *\"[aA][mM][dD]\"/\"module\": \"commonjs\"/g' tsconfig*.json && sed -i '/\"outFile\":/d' tsconfig*.json"

    # Instalamos dependencias y nos aseguramos de que playwright esté incluido
    run_stage "-> Instalando dependencias NPM..." "npm install && npm install playwright"

    # Intentamos localizar el binario de forma dinámica en lugar de forzar la ruta
    PLAYWRIGHT_PATH=$(find . -name playwright | grep ".bin/playwright" | head -n 1)

    run_stage "-> Descargando navegadores (Playwright)..." "$PLAYWRIGHT_PATH install chromium --with-deps"

    run_stage "-> Compilando (Nest Build)..." "npm run build"
fi

# 4. Despliegue
run_stage "-> Desplegando en /opt/hrafnar..." "rm -rf /opt/hrafnar && mkdir -p /opt/hrafnar && cp -r dist/* /opt/hrafnar/ && cp package.json /opt/hrafnar/ && cp -r node_modules /opt/hrafnar/"

# 5. Servicio Systemd
cat <<EOF > /etc/systemd/system/hrafnar.service
[Unit]
Description=Hrafnar Scraper Engine
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/hrafnar
Environment=PLAYWRIGHT_BROWSERS_PATH=/opt/hrafnar/ms-playwright
ExecStart=$(which xvfb-run) --auto-servernum --server-args="-screen 0 1280x1024x24" $(which node) /opt/hrafnar/main.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable hrafnar.service
systemctl restart hrafnar.service

echo "========================================================"
echo "  Instalación finalizada."
echo "  Servicio 'hrafnar' iniciado correctamente."
echo "========================================================"