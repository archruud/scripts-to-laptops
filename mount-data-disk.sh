#!/bin/bash
# mount-data-disk.sh - Mount Samsung 1TB Data disk til /home/archruud/Data

# Farger
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Disk info
DISK_UUID="ae626e33-a4d6-4dc5-8c60-238edfeb1649"
MOUNT_POINT="/home/archruud/Data"
DISK_TYPE="ext4"
USERNAME="archruud"

echo -e "${GREEN}╔════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   MOUNT DATA DISK - MEDION X10     ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════╝${NC}"
echo
echo -e "${BLUE}UUID:${NC} $DISK_UUID"
echo -e "${BLUE}Disk:${NC} nvme0n1p1 (Samsung 1TB)"
echo -e "${BLUE}Mount:${NC} $MOUNT_POINT"
echo -e "${BLUE}Type:${NC} $DISK_TYPE"
echo

# Steg 1: Verifiser at disken finnes
echo -e "${YELLOW}[1/7]${NC} Verifiserer disk..."
if ! lsblk -f | grep -q "$DISK_UUID"; then
    echo -e "${RED}✗ Feil: Disk ikke funnet!${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Disk funnet (nvme0n1p1)${NC}"

# Steg 2: Opprett monteringspunkt
echo -e "${YELLOW}[2/7]${NC} Oppretter monteringspunkt..."
if [ ! -d "$MOUNT_POINT" ]; then
    mkdir -p "$MOUNT_POINT"
    echo -e "${GREEN}✓ Mappe opprettet: $MOUNT_POINT${NC}"
else
    echo -e "${GREEN}✓ Mappe eksisterer${NC}"
fi

# Steg 3: Backup fstab
echo -e "${YELLOW}[3/7]${NC} Backup av /etc/fstab..."
if [ ! -f /etc/fstab.backup ]; then
    sudo cp /etc/fstab /etc/fstab.backup
    echo -e "${GREEN}✓ Backup: /etc/fstab.backup${NC}"
else
    echo -e "${GREEN}✓ Backup eksisterer${NC}"
fi

# Steg 4: Legg til fstab entry (med exec!)
echo -e "${YELLOW}[4/7]${NC} Konfigurerer fstab..."
FSTAB_LINE="UUID=$DISK_UUID    $MOUNT_POINT    $DISK_TYPE    defaults,rw,user,exec    0    2"

if grep -q "$DISK_UUID" /etc/fstab; then
    echo -e "${GREEN}✓ Entry eksisterer i fstab${NC}"
else
    echo "" | sudo tee -a /etc/fstab > /dev/null
    echo "# Data disk - Samsung 1TB (nvme0n1p1)" | sudo tee -a /etc/fstab > /dev/null
    echo "$FSTAB_LINE" | sudo tee -a /etc/fstab > /dev/null
    echo -e "${GREEN}✓ fstab oppdatert${NC}"
fi

# Steg 5: Mount disken
echo -e "${YELLOW}[5/7]${NC} Monterer disk..."
if mountpoint -q "$MOUNT_POINT"; then
    echo -e "${GREEN}✓ Allerede montert${NC}"
else
    if sudo mount -a; then
        echo -e "${GREEN}✓ Disk montert${NC}"
    else
        echo -e "${RED}✗ Montering feilet!${NC}"
        echo -e "${BLUE}Debug:${NC}"
        grep "$DISK_UUID" /etc/fstab
        exit 1
    fi
fi

# Steg 6: Sett rettigheter
echo -e "${YELLOW}[6/7]${NC} Setter rettigheter..."
sudo chown -R "$USERNAME:$USERNAME" "$MOUNT_POINT"
sudo chmod -R 755 "$MOUNT_POINT"
echo -e "${GREEN}✓ Rettigheter satt (archruud eier disken)${NC}"

# Steg 7: Verifiser
echo -e "${YELLOW}[7/7]${NC} Verifisering..."
echo

if mountpoint -q "$MOUNT_POINT"; then
    echo -e "${GREEN}✓ SUCCESS! Data disk montert${NC}"
    echo
    echo -e "${BLUE}Monteringsinformasjon:${NC}"
    df -h "$MOUNT_POINT" | tail -1
    echo
    echo -e "${BLUE}Mount options:${NC}"
    mount | grep "$MOUNT_POINT"
    echo
    
    # Test skrivetilgang
    if touch "$MOUNT_POINT/.test_write" 2>/dev/null; then
        rm "$MOUNT_POINT/.test_write"
        echo -e "${GREEN}✓ Skrivetilgang OK${NC}"
        echo -e "${GREEN}✓ Script-kjøring tillatt (exec)${NC}"
    else
        echo -e "${RED}✗ Ingen skrivetilgang!${NC}"
    fi
else
    echo -e "${RED}✗ Montering feilet!${NC}"
    exit 1
fi

echo
echo -e "${GREEN}╔════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           FERDIG! 🎉               ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════╝${NC}"
echo
echo -e "${BLUE}Data disk:${NC} /home/archruud/Data"
echo -e "${BLUE}Eier:${NC} archruud (full tilgang)"
echo -e "${BLUE}Auto-mount:${NC} Ja (ved oppstart)"
echo
echo -e "${YELLOW}Tips:${NC}"
echo -e "  • Disken monteres automatisk ved boot"
echo -e "  • Du kan kjøre scripts fra denne disken"
echo -e "  • For å avmontere: ${BLUE}sudo umount $MOUNT_POINT${NC}"


