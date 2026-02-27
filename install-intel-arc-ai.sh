#!/usr/bin/env bash
#==============================================================================
# install-intel-arc-ai.sh
# Intel Arc A730M GPU - AI/ML Driver & Toolkit Installasjon
# For: Medion Erazer Major X10 | Arch Linux Hyprland
# GPU:  Intel Arc A730M (DG2/Alchemist)
# RAM:  DDR5 64GB 4800MHz
#==============================================================================
set -euo pipefail

# ── Farger ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
info() { echo -e "${CYAN}[i]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; }

VENV_DIR="$HOME/.venvs/intel-ai"
LOGFILE="/tmp/install-intel-arc-ai-$(date +%Y%m%d-%H%M%S).log"

#==============================================================================
# Sjekker
#==============================================================================
header() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  Intel Arc A730M – AI/ML Driver & Toolkit Installasjon${NC}"
    echo -e "${BLUE}  Medion Erazer Major X10 | Arch Linux Hyprland${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

check_root() {
    if [[ $EUID -eq 0 ]]; then
        err "Ikke kjør som root. Scriptet bruker sudo der det trengs."
        exit 1
    fi
}

check_arch() {
    if [[ ! -f /etc/arch-release ]]; then
        err "Dette scriptet er kun for Arch Linux."
        exit 1
    fi
}

check_gpu() {
    info "Sjekker for Intel Arc GPU..."
    if lspci | grep -qi "Arc"; then
        log "Intel Arc GPU funnet:"
        lspci | grep -i "VGA\|Display\|3D" | grep -i "Intel" | sed 's/^/     /'
    else
        warn "Fant ikke Intel Arc GPU i lspci. Fortsetter likevel..."
    fi
}

check_render_device() {
    if [[ -e /dev/dri/renderD128 ]]; then
        log "Render-enhet /dev/dri/renderD128 tilgjengelig"
    else
        warn "/dev/dri/renderD128 ikke funnet – kan bety at GPU-driver mangler i kernel"
    fi
}

#==============================================================================
# Steg 1: Grunnleggende GPU-drivere (Mesa/Vulkan/VA-API)
#==============================================================================
install_gpu_drivers() {
    echo ""
    info "── Steg 1: GPU-drivere (Mesa, Vulkan, VA-API) ──"

    local pkgs=(
        # Mesa OpenGL/Vulkan (open source, i915/Xe kernel driver)
        mesa
        lib32-mesa
        vulkan-intel
        lib32-vulkan-intel
        vulkan-tools

        # Video akselerasjon (hardware decode/encode)
        intel-media-driver    # VA-API for Arc/Gen12+
        libva-utils

        # GPU-verktøy
        intel-gpu-tools       # intel_gpu_top, etc.
        clinfo                # OpenCL info
    )

    info "Installerer GPU-driverpakker..."
    sudo pacman -S --needed --noconfirm "${pkgs[@]}" 2>&1 | tee -a "$LOGFILE"
    log "GPU-drivere installert"
}

#==============================================================================
# Steg 2: Intel Compute Runtime & Level Zero (GPU compute)
#==============================================================================
install_compute_runtime() {
    echo ""
    info "── Steg 2: Intel Compute Runtime & Level Zero ──"

    local pkgs=(
        intel-compute-runtime    # NEO – OpenCL & Level Zero runtime for Arc
        intel-graphics-compiler  # Shader-kompilator for compute
        level-zero-loader        # Level Zero API loader
        level-zero-headers       # Level Zero headers
        ocl-icd                  # OpenCL ICD loader
    )

    sudo pacman -S --needed --noconfirm "${pkgs[@]}" 2>&1 | tee -a "$LOGFILE"
    log "Compute runtime installert"

    # Verifiser Level Zero
    if command -v ze_info &>/dev/null; then
        info "Level Zero enheter:"
        ze_info 2>/dev/null | head -20 || true
    fi
}

#==============================================================================
# Steg 3: Intel oneAPI Base Toolkit (MKL, DNN, SYCL, DPC++)
#==============================================================================
install_oneapi() {
    echo ""
    info "── Steg 3: Intel oneAPI Base Toolkit ──"
    warn "MERK: intel-oneapi-basekit er ~25GB. Dette tar tid!"
    echo ""

    read -rp "Vil du installere intel-oneapi-basekit? (j/n): " svar
    if [[ "$svar" =~ ^[jJyY]$ ]]; then
        sudo pacman -S --needed --noconfirm intel-oneapi-basekit 2>&1 | tee -a "$LOGFILE"
        log "oneAPI Base Toolkit installert"

        # Sett opp environment-variabler
        setup_oneapi_env
    else
        warn "Hopper over oneAPI Base Toolkit."
        info "Du kan installere det senere med: sudo pacman -S intel-oneapi-basekit"
    fi
}

setup_oneapi_env() {
    info "Setter opp oneAPI environment..."

    local profile_file="$HOME/.config/environment.d/intel-oneapi.conf"
    mkdir -p "$(dirname "$profile_file")"

    # systemd environment.d for Hyprland/Wayland sessions
    cat > "$profile_file" << 'EOF'
# Intel oneAPI environment variabler
# Lastet automatisk av systemd for grafiske sesjoner
# Kjør 'source /opt/intel/oneapi/setvars.sh' for full shell-setup
EOF

    # Shell profile snippet
    local shell_snippet="$HOME/.config/shell/intel-oneapi.sh"
    mkdir -p "$(dirname "$shell_snippet")"
    cat > "$shell_snippet" << 'SHELLEOF'
#!/bin/bash
# Intel oneAPI environment – source dette i .bashrc/.zshrc
# eller kjør: source /opt/intel/oneapi/setvars.sh
if [[ -f /opt/intel/oneapi/setvars.sh ]]; then
    # Kun sett opp om ikke allerede gjort
    if [[ -z "${ONEAPI_ROOT:-}" ]]; then
        source /opt/intel/oneapi/setvars.sh --force > /dev/null 2>&1
    fi
fi
SHELLEOF

    # Legg til i .bashrc om den finnes
    if [[ -f "$HOME/.bashrc" ]]; then
        if ! grep -q "intel-oneapi.sh" "$HOME/.bashrc" 2>/dev/null; then
            echo "" >> "$HOME/.bashrc"
            echo "# Intel oneAPI" >> "$HOME/.bashrc"
            echo "[[ -f ~/.config/shell/intel-oneapi.sh ]] && source ~/.config/shell/intel-oneapi.sh" >> "$HOME/.bashrc"
            log "Lagt til oneAPI source i .bashrc"
        fi
    fi

    # Legg til i .zshrc om den finnes
    if [[ -f "$HOME/.zshrc" ]]; then
        if ! grep -q "intel-oneapi.sh" "$HOME/.zshrc" 2>/dev/null; then
            echo "" >> "$HOME/.zshrc"
            echo "# Intel oneAPI" >> "$HOME/.zshrc"
            echo "[[ -f ~/.config/shell/intel-oneapi.sh ]] && source ~/.config/shell/intel-oneapi.sh" >> "$HOME/.zshrc"
            log "Lagt til oneAPI source i .zshrc"
        fi
    fi

    log "oneAPI environment konfigurert"
}

#==============================================================================
# Steg 4: Python AI-miljø med PyTorch XPU
#==============================================================================
install_python_ai() {
    echo ""
    info "── Steg 4: Python AI-miljø (PyTorch XPU) ──"

    # Sørg for at python og venv er installert
    sudo pacman -S --needed --noconfirm python python-pip python-virtualenv 2>&1 | tee -a "$LOGFILE"

    # Opprett venv
    if [[ -d "$VENV_DIR" ]]; then
        warn "Virtuelt miljø finnes allerede: $VENV_DIR"
        read -rp "Slett og lag på nytt? (j/n): " svar
        if [[ "$svar" =~ ^[jJyY]$ ]]; then
            rm -rf "$VENV_DIR"
        else
            info "Bruker eksisterende venv."
        fi
    fi

    if [[ ! -d "$VENV_DIR" ]]; then
        info "Oppretter Python venv: $VENV_DIR"
        python -m venv "$VENV_DIR"
    fi

    # Aktiver og installer
    source "$VENV_DIR/bin/activate"

    info "Oppgraderer pip..."
    pip install --upgrade pip 2>&1 | tee -a "$LOGFILE"

    info "Installerer PyTorch med XPU-støtte (Intel Arc)..."
    pip install \
        torch torchvision torchaudio \
        intel-cmplr-lib-rt intel-cmplr-lib-ur intel-cmplr-lic-rt \
        intel-sycl-rt pytorch-triton-xpu tcmlib umf intel-pti \
        --index-url https://download.pytorch.org/whl/xpu \
        --extra-index-url https://pypi.org/simple \
        2>&1 | tee -a "$LOGFILE"

    info "Installerer vanlige AI/ML-biblioteker..."
    pip install \
        numpy scipy pandas scikit-learn \
        transformers accelerate datasets \
        jupyter notebook \
        onnx onnxruntime \
        2>&1 | tee -a "$LOGFILE"

    log "Python AI-miljø installert i: $VENV_DIR"

    deactivate
}

#==============================================================================
# Steg 5: Ollama for lokal LLM-inferens
#==============================================================================
install_ollama() {
    echo ""
    info "── Steg 5: Ollama (Lokal LLM) ──"

    read -rp "Vil du installere Ollama for lokal LLM-inferens? (j/n): " svar
    if [[ "$svar" =~ ^[jJyY]$ ]]; then
        if command -v ollama &>/dev/null; then
            warn "Ollama er allerede installert."
        else
            info "Installerer Ollama..."
            curl -fsSL https://ollama.com/install.sh | sh 2>&1 | tee -a "$LOGFILE"
        fi

        # Sett Intel GPU-miljø for Ollama
        local ollama_env="/etc/environment.d/ollama-intel.conf"
        sudo mkdir -p /etc/environment.d
        echo "# Ollama Intel Arc GPU-akselerasjon" | sudo tee "$ollama_env" > /dev/null
        echo "OLLAMA_INTEL_GPU=1" | sudo tee -a "$ollama_env" > /dev/null

        log "Ollama installert"
        info "Start med: ollama serve"
        info "Test med:  ollama run llama3.2"
    else
        warn "Hopper over Ollama."
    fi
}

#==============================================================================
# Steg 6: Brukergrupper og rettigheter
#==============================================================================
setup_permissions() {
    echo ""
    info "── Steg 6: Brukergrupper og rettigheter ──"

    # render og video grupper for GPU-tilgang
    for grp in render video; do
        if id -nG "$USER" | grep -qw "$grp"; then
            log "Bruker '$USER' er allerede i gruppen '$grp'"
        else
            sudo usermod -aG "$grp" "$USER"
            log "La til '$USER' i gruppen '$grp'"
        fi
    done
}

#==============================================================================
# Steg 7: Verifisering
#==============================================================================
verify_install() {
    echo ""
    info "── Steg 7: Verifisering ──"

    echo ""
    info "GPU-enheter:"
    ls -la /dev/dri/ 2>/dev/null || warn "Ingen /dev/dri/ funnet"

    echo ""
    info "Intel GPU (lspci):"
    lspci | grep -i "VGA\|Display\|3D" | grep -i "Intel" || true

    echo ""
    info "Vulkan:"
    if command -v vulkaninfo &>/dev/null; then
        vulkaninfo --summary 2>/dev/null | grep -E "GPU|driver" | head -5 || true
    fi

    echo ""
    info "OpenCL:"
    if command -v clinfo &>/dev/null; then
        clinfo --list 2>/dev/null || true
    fi

    echo ""
    info "VA-API (video akselerasjon):"
    if command -v vainfo &>/dev/null; then
        vainfo 2>/dev/null | head -5 || true
    fi

    # PyTorch XPU sjekk
    if [[ -d "$VENV_DIR" ]]; then
        echo ""
        info "PyTorch XPU verifisering:"
        source "$VENV_DIR/bin/activate"
        python3 -c "
import torch
print(f'  PyTorch versjon: {torch.__version__}')
if torch.xpu.is_available():
    print(f'  XPU tilgjengelig: Ja')
    print(f'  Antall XPU-enheter: {torch.xpu.device_count()}')
    for i in range(torch.xpu.device_count()):
        print(f'  Enhet {i}: {torch.xpu.get_device_name(i)}')
    x = torch.randn(256, 256, device='xpu')
    y = torch.randn(256, 256, device='xpu')
    z = torch.mm(x, y)
    print(f'  Matrise-multiplikasjon test: OK ({z.device})')
else:
    print('  XPU tilgjengelig: Nei')
    print('  Tips: Prøv å logge ut/inn eller reboot for å oppdatere grupper')
" 2>/dev/null || warn "PyTorch XPU-test feilet – prøv etter reboot"
        deactivate
    fi
}

#==============================================================================
# Oppsummering
#==============================================================================
summary() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  Installasjon fullført!${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${CYAN}Hva ble installert:${NC}"
    echo "  • Mesa/Vulkan/VA-API drivere for Intel Arc"
    echo "  • Intel Compute Runtime (OpenCL + Level Zero)"
    echo "  • Intel oneAPI Base Toolkit (om valgt)"
    echo "  • Python AI-miljø med PyTorch XPU"
    echo "  • Ollama lokal LLM (om valgt)"
    echo ""
    echo -e "  ${CYAN}Viktige kommandoer:${NC}"
    echo "  • Aktiver AI venv:   source $VENV_DIR/bin/activate"
    echo "  • oneAPI setup:      source /opt/intel/oneapi/setvars.sh"
    echo "  • GPU-monitor:       intel_gpu_top"
    echo "  • Vulkan info:       vulkaninfo --summary"
    echo "  • OpenCL info:       clinfo"
    echo ""
    echo -e "  ${CYAN}Logg:${NC} $LOGFILE"
    echo ""
    echo -e "  ${YELLOW}⚠  REBOOT anbefales for at gruppemedlemskap skal tre i kraft.${NC}"
    echo ""
}

#==============================================================================
# Main
#==============================================================================
main() {
    header
    check_root
    check_arch
    check_gpu
    check_render_device

    install_gpu_drivers
    install_compute_runtime
    install_oneapi
    install_python_ai
    install_ollama
    setup_permissions
    verify_install
    summary
}

main "$@"
