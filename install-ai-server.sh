#!/bin/bash
# ============================================================
# AI Server Install Script
# Debian 12 LXC Container - VLAN 30
# Installerer: NVIDIA drivers, Docker CE, Ollama, Open WebUI
# Kjør som root: bash install-ai-server.sh
# ============================================================

set -e

# ── Farger ──────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()    { echo -e "${GREEN}[✓] $1${NC}"; }
warn()   { echo -e "${YELLOW}[!] $1${NC}"; }
error()  { echo -e "${RED}[✗] $1${NC}"; exit 1; }
header() { echo -e "\n${BLUE}══════════════════════════════════════${NC}"; echo -e "${BLUE}  $1${NC}"; echo -e "${BLUE}══════════════════════════════════════${NC}"; }

# ── Sjekk root ───────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    error "Kjør scriptet som root: sudo bash $0"
fi

# ── Konfigurasjon ────────────────────────────────────────────
header "Konfigurasjon"

# Open WebUI port
WEBUI_PORT=3000
# Portainer port
PORTAINER_PORT=9000
# Ollama port
OLLAMA_PORT=11434

echo -e "Open WebUI:  http://$(hostname -I | awk '{print $1}'):${WEBUI_PORT}"
echo -e "Portainer:   http://$(hostname -I | awk '{print $1}'):${PORTAINER_PORT}"
echo -e "Ollama API:  http://$(hostname -I | awk '{print $1}'):${OLLAMA_PORT}"
echo ""
read -p "Fortsett med installasjon? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Avbryt."
    exit 0
fi

# ── Steg 1: Oppdater system ──────────────────────────────────
header "Steg 1: Oppdaterer system"
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq \
    curl wget git nano htop \
    ca-certificates gnupg \
    apt-transport-https \
    software-properties-common \
    lsb-release \
    build-essential \
    pciutils usbutils \
    zstd
log "System oppdatert"

# ── Steg 2: NVIDIA driver i LXC ─────────────────────────────
header "Steg 2: NVIDIA drivers (LXC modus)"

# I LXC trenger vi bare user-space biblioteker, ikke kernel-moduler
# Kernel-modulene er på Proxmox-hosten
if nvidia-smi &>/dev/null; then
    log "NVIDIA GPU funnet og fungerer allerede!"
    nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader
else
    warn "nvidia-smi ikke funnet - installerer NVIDIA user-space pakker"
    
    # Legg til NVIDIA repo
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
        gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    
    apt-get update -qq
    apt-get install -y nvidia-container-toolkit
    
    log "NVIDIA Container Toolkit installert"
fi

# ── Steg 3: Docker CE ────────────────────────────────────────
header "Steg 3: Installerer Docker CE"

if command -v docker &>/dev/null; then
    warn "Docker er allerede installert: $(docker --version)"
else
    # Fjern gamle versjoner
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Legg til Docker repo
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | \
        gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/debian $(lsb_release -cs) stable" | \
        tee /etc/apt/sources.list.d/docker.list
    
    apt-get update -qq
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    systemctl enable docker
    systemctl start docker
    log "Docker CE installert: $(docker --version)"
fi

# ── Steg 4: Konfigurer Docker med NVIDIA ────────────────────
header "Steg 4: Konfigurerer Docker + NVIDIA"

nvidia-ctk runtime configure --runtime=docker
systemctl restart docker
log "Docker NVIDIA runtime konfigurert"

# Test GPU i Docker
if docker run --rm --gpus all nvidia/cuda:12.6.0-base-debian12 nvidia-smi &>/dev/null; then
    log "GPU fungerer i Docker!"
else
    warn "GPU test i Docker feilet - sjekk LXC konfig på Proxmox"
fi

# ── Steg 5: Portainer ────────────────────────────────────────
header "Steg 5: Installerer Portainer CE"

if docker ps -a --format '{{.Names}}' | grep -q "^portainer$"; then
    warn "Portainer kjører allerede"
else
    docker volume create portainer_data
    docker run -d \
        -p ${PORTAINER_PORT}:9000 \
        --name portainer \
        --restart always \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v portainer_data:/data \
        portainer/portainer-ce:latest
    log "Portainer installert på port ${PORTAINER_PORT}"
fi

# ── Steg 6: Ollama ───────────────────────────────────────────
header "Steg 6: Installerer Ollama"

if command -v ollama &>/dev/null; then
    warn "Ollama er allerede installert: $(ollama --version)"
else
    curl -fsSL https://ollama.com/install.sh | sh
    log "Ollama installert"
fi

# Konfigurer Ollama til å lytte på alle grensesnitt
mkdir -p /etc/systemd/system/ollama.service.d
cat > /etc/systemd/system/ollama.service.d/override.conf << 'EOF'
[Service]
Environment="OLLAMA_HOST=0.0.0.0"
Environment="OLLAMA_ORIGINS=*"
EOF

systemctl daemon-reload
systemctl enable ollama
systemctl restart ollama
sleep 3

if systemctl is-active --quiet ollama; then
    log "Ollama kjører og lytter på 0.0.0.0:${OLLAMA_PORT}"
else
    error "Ollama startet ikke - sjekk: journalctl -u ollama"
fi

# ── Steg 7: Last ned anbefalte modeller ─────────────────────
header "Steg 7: Laster ned AI-modeller"

echo "Med 48GB VRAM (2xA2 + T4) kan du kjøre store modeller!"
echo ""
echo "Velg hvilke modeller du vil installere:"
echo "1) Basis pakke    - mistral:7b + llama3.1:8b (rask, ~10GB)"
echo "2) Kraftig pakke  - qwen2.5:32b + deepseek-r1:32b (~40GB)"
echo "3) Maks pakke     - llama3.3:70b + qwen2.5:72b (~80GB, bruker litt swap)"
echo "4) Ingen          - installer manuelt senere"
echo ""
read -p "Velg (1-4): " model_choice

case $model_choice in
    1)
        log "Laster ned basis pakke..."
        ollama pull mistral:latest
        ollama pull llama3.1:8b
        ;;
    2)
        log "Laster ned kraftig pakke (tar litt tid)..."
        ollama pull qwen2.5:32b
        ollama pull deepseek-r1:32b
        ;;
    3)
        log "Laster ned maks pakke (tar lang tid)..."
        ollama pull llama3.3:70b
        ollama pull qwen2.5:72b
        ;;
    4)
        warn "Hopper over modeller - last ned manuelt med: ollama pull <modell>"
        ;;
    *)
        warn "Ugyldig valg - hopper over"
        ;;
esac

# ── Steg 8: Open WebUI ───────────────────────────────────────
header "Steg 8: Installerer Open WebUI"

HOST_IP=$(hostname -I | awk '{print $1}')

if docker ps -a --format '{{.Names}}' | grep -q "^open-webui$"; then
    warn "Open WebUI kjører allerede - restarter med riktig konfig"
    docker stop open-webui
    docker rm open-webui
fi

docker run -d \
    -p ${WEBUI_PORT}:8080 \
    -e OLLAMA_BASE_URL=http://${HOST_IP}:${OLLAMA_PORT} \
    -e WEBUI_SECRET_KEY=$(openssl rand -hex 32) \
    -v open-webui:/app/backend/data \
    --name open-webui \
    --restart always \
    ghcr.io/open-webui/open-webui:main

sleep 5

if docker ps --format '{{.Names}}' | grep -q "^open-webui$"; then
    log "Open WebUI installert og kjører!"
else
    error "Open WebUI startet ikke - sjekk: docker logs open-webui"
fi

# ── Steg 9: Brannmur (valgfritt) ────────────────────────────
header "Steg 9: Nettverksinfo VLAN 30"

echo -e "${YELLOW}Husk å åpne disse portene i UniFi/brannmur for VLAN 30:${NC}"
echo "  Port 3000  - Open WebUI"
echo "  Port 9000  - Portainer"
echo "  Port 11434 - Ollama API"

# ── Ferdig ───────────────────────────────────────────────────
header "🎉 Installasjon fullført!"

HOST_IP=$(hostname -I | awk '{print $1}')

echo -e "${GREEN}"
echo "  ╔════════════════════════════════════════════╗"
echo "  ║           TILGANG TIL TJENESTER            ║"
echo "  ╠════════════════════════════════════════════╣"
echo "  ║  Open WebUI:  http://${HOST_IP}:${WEBUI_PORT}          ║"
echo "  ║  Portainer:   http://${HOST_IP}:${PORTAINER_PORT}          ║"
echo "  ║  Ollama API:  http://${HOST_IP}:${OLLAMA_PORT}        ║"
echo "  ╠════════════════════════════════════════════╣"
echo "  ║  Last ned modeller:                        ║"
echo "  ║  ollama pull qwen2.5:32b                   ║"
echo "  ║  ollama pull deepseek-r1:70b               ║"
echo "  ║  ollama pull llama3.3:70b                  ║"
echo "  ╚════════════════════════════════════════════╝"
echo -e "${NC}"

# Sjekk GPU status
echo -e "\n${BLUE}GPU Status:${NC}"
nvidia-smi --query-gpu=name,memory.total,memory.free --format=csv,noheader 2>/dev/null || \
    warn "nvidia-smi ikke tilgjengelig - sjekk GPU passthrough i Proxmox"

echo -e "\n${BLUE}Kjørende containere:${NC}"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
