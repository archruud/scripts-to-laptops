#!/bin/bash
# pacmanfix.sh - Fix Arch keyring før installasjon
# archruud - scripts-to-laptops

echo "╔════════════════════════════════════╗"
echo "║   ARCH KEYRING FIX                 ║"
echo "╚════════════════════════════════════╝"
echo

echo "[1/4] Oppdaterer package database..."
pacman -Sy --noconfirm || {
    echo "Feil ved pacman -Sy, prøver igjen..."
    sleep 2
    pacman -Sy --noconfirm
}

echo "[2/4] Oppdaterer archlinux-keyring..."
pacman -S --noconfirm archlinux-keyring || {
    echo "Keyring update feilet, prøver force..."
    pacman -S --noconfirm --overwrite '*' archlinux-keyring
}

echo "[3/4] Initialiserer pacman keys..."
pacman-key --init

echo "[4/4] Populerer Arch Linux keys..."
pacman-key --populate archlinux

echo
echo "✓ Keyring fikset! Klar for installasjon."
echo
