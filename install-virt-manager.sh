#!/usr/bin/env bash
#==============================================================================
# install-virt-manager.sh
# Virt-Manager + Full QEMU/KVM Installasjon
# For: Medion Erazer Major X10 | Arch Linux Hyprland
# Nettverk: Enkel NAT (standard default) – laptop-bruker
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

LOGFILE="/tmp/install-virt-manager-$(date +%Y%m%d-%H%M%S).log"
USERNAME="$(whoami)"

#==============================================================================
# Sjekker
#==============================================================================
header() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  Virt-Manager + QEMU/KVM Full Installasjon${NC}"
    echo -e "${BLUE}  Medion Erazer Major X10 | Arch Linux Hyprland${NC}"
    echo -e "${BLUE}  Nettverk: Enkel NAT (default virbr0)${NC}"
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

check_virtualization() {
    info "Sjekker hardware-virtualisering..."

    local vt_support
    vt_support=$(grep -cE '(vmx|svm)' /proc/cpuinfo 2>/dev/null || echo "0")

    if [[ "$vt_support" -gt 0 ]]; then
        if grep -q "vmx" /proc/cpuinfo; then
            log "Intel VT-x støtte funnet (${vt_support} tråder)"
        elif grep -q "svm" /proc/cpuinfo; then
            log "AMD-V støtte funnet (${vt_support} tråder)"
        fi
    else
        err "Ingen hardware-virtualisering funnet!"
        err "Aktiver Intel VT-x / AMD-V i BIOS/UEFI og prøv igjen."
        exit 1
    fi

    # Sjekk at kvm-modulen er lastet
    if lsmod | grep -q "kvm"; then
        log "KVM kernel-modul er lastet"
    else
        warn "KVM kernel-modul er ikke lastet. Prøver å laste..."
        if grep -q "Intel" /proc/cpuinfo; then
            sudo modprobe kvm_intel 2>/dev/null || warn "Kunne ikke laste kvm_intel"
        else
            sudo modprobe kvm_amd 2>/dev/null || warn "Kunne ikke laste kvm_amd"
        fi
    fi
}

#==============================================================================
# Steg 1: KVM kernel-moduler (autoload ved boot)
#==============================================================================
setup_kvm_modules() {
    echo ""
    info "── Steg 1: KVM Kernel-moduler ──"

    local kvm_conf="/etc/modules-load.d/kvm.conf"

    if grep -q "Intel" /proc/cpuinfo; then
        echo -e "kvm\nkvm_intel" | sudo tee "$kvm_conf" > /dev/null
        log "Konfigurert autoload: kvm + kvm_intel"
    else
        echo -e "kvm\nkvm_amd" | sudo tee "$kvm_conf" > /dev/null
        log "Konfigurert autoload: kvm + kvm_amd"
    fi
}

#==============================================================================
# Steg 2: Installer QEMU, libvirt, virt-manager og verktøy
#==============================================================================
install_packages() {
    echo ""
    info "── Steg 2: QEMU/KVM pakker ──"

    local pkgs=(
        # QEMU (full – alle arkitekturer + GUI)
        qemu-full

        # Libvirt daemon og verktøy
        libvirt

        # Virt-Manager GUI + viewer
        virt-manager
        virt-viewer
        virt-install

        # Nettverk (NAT via dnsmasq)
        dnsmasq
        iptables-nft           # nftables backend for iptables

        # UEFI firmware for VM-er
        edk2-ovmf

        # TPM-emulering (nødvendig for Windows 11 VM)
        swtpm

        # Nyttige tilleggsverktøy
        libguestfs             # VM disk image-verktøy
        libosinfo              # OS-database for virt-install
        dmidecode              # Hardware info (brukes av libvirt)
    )

    info "Installerer pakker..."
    sudo pacman -S --needed --noconfirm "${pkgs[@]}" 2>&1 | tee -a "$LOGFILE"
    log "Alle QEMU/KVM-pakker installert"
}

#==============================================================================
# Steg 3: Brukergrupper
#==============================================================================
setup_groups() {
    echo ""
    info "── Steg 3: Brukergrupper ──"

    for grp in libvirt kvm; do
        if id -nG "$USERNAME" | grep -qw "$grp"; then
            log "'$USERNAME' er allerede i gruppen '$grp'"
        else
            sudo usermod -aG "$grp" "$USERNAME"
            log "La til '$USERNAME' i gruppen '$grp'"
        fi
    done
}

#==============================================================================
# Steg 4: Libvirt daemon-konfigurasjon
#==============================================================================
configure_libvirt() {
    echo ""
    info "── Steg 4: Libvirt konfigurasjon ──"

    # ── libvirtd.conf: Tillat socket-tilgang for libvirt-gruppen ─────────
    local libvirtd_conf="/etc/libvirt/libvirtd.conf"

    # Unix socket gruppe
    if ! grep -q '^unix_sock_group = "libvirt"' "$libvirtd_conf" 2>/dev/null; then
        sudo sed -i 's/^#\?unix_sock_group\s*=.*/unix_sock_group = "libvirt"/' "$libvirtd_conf"
        # Om sed ikke fant linjen, legg den til
        if ! grep -q '^unix_sock_group = "libvirt"' "$libvirtd_conf"; then
            echo 'unix_sock_group = "libvirt"' | sudo tee -a "$libvirtd_conf" > /dev/null
        fi
        log "Satt unix_sock_group = libvirt"
    else
        log "unix_sock_group allerede konfigurert"
    fi

    # Unix socket read-write rettigheter
    if ! grep -q '^unix_sock_rw_perms = "0770"' "$libvirtd_conf" 2>/dev/null; then
        sudo sed -i 's/^#\?unix_sock_rw_perms\s*=.*/unix_sock_rw_perms = "0770"/' "$libvirtd_conf"
        if ! grep -q '^unix_sock_rw_perms = "0770"' "$libvirtd_conf"; then
            echo 'unix_sock_rw_perms = "0770"' | sudo tee -a "$libvirtd_conf" > /dev/null
        fi
        log "Satt unix_sock_rw_perms = 0770"
    else
        log "unix_sock_rw_perms allerede konfigurert"
    fi

    # ── qemu.conf: Sett bruker for QEMU-prosesser ───────────────────────
    local qemu_conf="/etc/libvirt/qemu.conf"

    # Sett user og group til gjeldende bruker for å unngå tilgangsproblemer
    if ! grep -q "^user = \"$USERNAME\"" "$qemu_conf" 2>/dev/null; then
        sudo sed -i "s/^#\?user\s*=.*/user = \"$USERNAME\"/" "$qemu_conf"
        if ! grep -q "^user = \"$USERNAME\"" "$qemu_conf"; then
            echo "user = \"$USERNAME\"" | sudo tee -a "$qemu_conf" > /dev/null
        fi
        log "Satt QEMU user = $USERNAME"
    else
        log "QEMU user allerede konfigurert"
    fi

    if ! grep -q "^group = \"$USERNAME\"" "$qemu_conf" 2>/dev/null; then
        sudo sed -i "s/^#\?group\s*=.*/group = \"$USERNAME\"/" "$qemu_conf"
        if ! grep -q "^group = \"$USERNAME\"" "$qemu_conf"; then
            echo "group = \"$USERNAME\"" | sudo tee -a "$qemu_conf" > /dev/null
        fi
        log "Satt QEMU group = $USERNAME"
    else
        log "QEMU group allerede konfigurert"
    fi
}

#==============================================================================
# Steg 5: Polkit-regel for libvirt uten passord
#==============================================================================
setup_polkit() {
    echo ""
    info "── Steg 5: Polkit-regel for libvirt ──"

    local polkit_rule="/etc/polkit-1/rules.d/50-libvirt.rules"

    if [[ -f "$polkit_rule" ]]; then
        log "Polkit-regel finnes allerede: $polkit_rule"
    else
        sudo tee "$polkit_rule" > /dev/null << 'EOF'
/* Tillat brukere i libvirt-gruppen å administrere VM-er uten passord */
polkit.addRule(function(action, subject) {
    if (action.id == "org.libvirt.unix.manage" &&
        subject.isInGroup("libvirt")) {
        return polkit.Result.YES;
    }
});
EOF
        log "Polkit-regel opprettet – libvirt-gruppen kan styre VM-er"
    fi
}

#==============================================================================
# Steg 6: Start og aktiver tjenester
#==============================================================================
enable_services() {
    echo ""
    info "── Steg 6: Systemd-tjenester ──"

    # Monolittisk daemon (enklest for laptop-bruk)
    sudo systemctl enable --now libvirtd.service 2>&1 | tee -a "$LOGFILE"
    log "libvirtd.service aktivert og startet"

    # Socket for on-demand oppstart
    sudo systemctl enable libvirtd.socket 2>&1 | tee -a "$LOGFILE"
    log "libvirtd.socket aktivert"

    # Sjekk status
    if systemctl is-active --quiet libvirtd; then
        log "libvirtd kjører"
    else
        warn "libvirtd startet ikke – sjekk: systemctl status libvirtd"
    fi
}

#==============================================================================
# Steg 7: Standard NAT-nettverk (default)
#==============================================================================
setup_network() {
    echo ""
    info "── Steg 7: NAT-nettverk (default virbr0) ──"

    # Definer default-nettverk om det ikke finnes
    if sudo virsh net-info default &>/dev/null; then
        log "Default-nettverk finnes allerede"
    else
        info "Definerer default NAT-nettverk..."
        sudo virsh net-define /usr/share/libvirt/networks/default.xml 2>&1 | tee -a "$LOGFILE"
        log "Default-nettverk definert"
    fi

    # Start nettverket
    if sudo virsh net-list --all | grep -q "default.*active"; then
        log "Default-nettverk er allerede aktivt"
    else
        sudo virsh net-start default 2>&1 | tee -a "$LOGFILE" || true
        log "Default-nettverk startet"
    fi

    # Autostart ved boot
    sudo virsh net-autostart default 2>&1 | tee -a "$LOGFILE" || true
    log "Default-nettverk satt til autostart"

    echo ""
    info "Nettverksstatus:"
    sudo virsh net-list --all 2>/dev/null | sed 's/^/     /'
}

#==============================================================================
# Steg 8: Standard lagringspool
#==============================================================================
setup_storage() {
    echo ""
    info "── Steg 8: Standard lagringspool ──"

    local pool_dir="$HOME/.local/share/libvirt/images"
    mkdir -p "$pool_dir"

    # Sjekk om default pool finnes
    if sudo virsh pool-info default &>/dev/null; then
        log "Default lagringspool finnes allerede"
    else
        info "Oppretter standard lagringspool i $pool_dir..."
        sudo virsh pool-define-as default dir --target "$pool_dir" 2>&1 | tee -a "$LOGFILE"
        sudo virsh pool-build default 2>&1 | tee -a "$LOGFILE" || true
        sudo virsh pool-start default 2>&1 | tee -a "$LOGFILE"
        sudo virsh pool-autostart default 2>&1 | tee -a "$LOGFILE"
        log "Lagringspool opprettet: $pool_dir"
    fi

    # ISO-mappe for installasjonsmedier
    local iso_dir="$HOME/.local/share/libvirt/iso"
    mkdir -p "$iso_dir"

    if ! sudo virsh pool-info iso &>/dev/null; then
        sudo virsh pool-define-as iso dir --target "$iso_dir" 2>&1 | tee -a "$LOGFILE"
        sudo virsh pool-build iso 2>&1 | tee -a "$LOGFILE" || true
        sudo virsh pool-start iso 2>&1 | tee -a "$LOGFILE"
        sudo virsh pool-autostart iso 2>&1 | tee -a "$LOGFILE"
        log "ISO-pool opprettet: $iso_dir"
    else
        log "ISO-pool finnes allerede"
    fi
}

#==============================================================================
# Steg 9: Hyprland-integrasjon (valgfritt)
#==============================================================================
setup_hyprland_keybind() {
    echo ""
    info "── Steg 9: Hyprland tips ──"

    echo ""
    info "For å legge til hurtigtast i Hyprland, legg dette i hyprland.conf:"
    echo ""
    echo -e "  ${CYAN}# Virt-Manager hurtigtast${NC}"
    echo -e "  ${CYAN}bind = SUPER SHIFT, V, exec, virt-manager${NC}"
    echo ""
}

#==============================================================================
# Steg 10: Verifisering
#==============================================================================
verify_install() {
    echo ""
    info "── Steg 10: Verifisering ──"

    echo ""
    info "KVM kernel-modul:"
    if lsmod | grep -q kvm; then
        lsmod | grep kvm | sed 's/^/     /'
        log "KVM modul lastet"
    else
        warn "KVM modul ikke lastet"
    fi

    echo ""
    info "QEMU versjon:"
    qemu-system-x86_64 --version 2>/dev/null | head -1 | sed 's/^/     /' || warn "QEMU ikke funnet"

    echo ""
    info "Libvirt versjon:"
    virsh --version 2>/dev/null | sed 's/^/     /' || warn "virsh ikke funnet"

    echo ""
    info "Virt-Manager versjon:"
    virt-manager --version 2>/dev/null | sed 's/^/     /' || warn "virt-manager ikke funnet"

    echo ""
    info "Libvirt tilkobling:"
    if virsh -c qemu:///system list --all &>/dev/null; then
        log "qemu:///system tilkobling OK"
        virsh -c qemu:///system list --all 2>/dev/null | sed 's/^/     /'
    else
        warn "Kunne ikke koble til qemu:///system – prøv etter reboot"
    fi

    echo ""
    info "Nettverk:"
    sudo virsh net-list --all 2>/dev/null | sed 's/^/     /'

    echo ""
    info "Lagringspooler:"
    sudo virsh pool-list --all 2>/dev/null | sed 's/^/     /'
}

#==============================================================================
# Oppsummering
#==============================================================================
summary() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  Virt-Manager installasjon fullført!${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${CYAN}Hva ble installert:${NC}"
    echo "  • QEMU full (alle arkitekturer)"
    echo "  • Libvirt daemon + virsh"
    echo "  • Virt-Manager GUI + virt-viewer"
    echo "  • OVMF UEFI firmware"
    echo "  • swtpm (TPM-emulering for Windows 11)"
    echo "  • NAT-nettverk (default/virbr0)"
    echo ""
    echo -e "  ${CYAN}Nettverk:${NC}"
    echo "  • Type: NAT via virbr0 (dnsmasq)"
    echo "  • Subnet: 192.168.122.0/24 (standard)"
    echo "  • VM-er får internett via laptop-tilkobling"
    echo "  • Ingen bridge-konfigurasjon nødvendig"
    echo ""
    echo -e "  ${CYAN}Lagring:${NC}"
    echo "  • VM-disker:  ~/.local/share/libvirt/images/"
    echo "  • ISO-filer:  ~/.local/share/libvirt/iso/"
    echo ""
    echo -e "  ${CYAN}Viktige kommandoer:${NC}"
    echo "  • Start GUI:        virt-manager"
    echo "  • Liste VM-er:      virsh list --all"
    echo "  • Start VM:         virsh start <navn>"
    echo "  • Stopp VM:         virsh shutdown <navn>"
    echo "  • Nettverk:         virsh net-list --all"
    echo ""
    echo -e "  ${CYAN}Logg:${NC} $LOGFILE"
    echo ""
    echo -e "  ${YELLOW}⚠  REBOOT anbefales for at gruppemedlemskap trer i kraft.${NC}"
    echo ""
    echo -e "  ${CYAN}Tips: Legg ISO-filer i ~/.local/share/libvirt/iso/${NC}"
    echo -e "  ${CYAN}      så dukker de opp i Virt-Manager sin filvelger.${NC}"
    echo ""
}

#==============================================================================
# Main
#==============================================================================
main() {
    header
    check_root
    check_arch
    check_virtualization

    setup_kvm_modules
    install_packages
    setup_groups
    configure_libvirt
    setup_polkit
    enable_services
    setup_network
    setup_storage
    setup_hyprland_keybind
    verify_install
    summary
}

main "$@"
