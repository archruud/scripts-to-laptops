#!/bin/bash

# SWWW Wallpaper Setter - Archruud
# Dette scriptet starter swww daemon og setter wallpaper

WALLPAPER_DIR="$HOME/.config/hypr/wallpapers"
WALLPAPER_FILE="ARCHRUUD_1920x1200.png"

# Start swww daemon (hvis ikke allerede kjører)
if ! pgrep -x swww-daemon > /dev/null; then
    swww-daemon &
    sleep 1
fi

# Sett wallpaper med fade transition
swww img "$WALLPAPER_DIR/$WALLPAPER_FILE" \
    --transition-type fade \
    --transition-duration 2 \
    --transition-fps 60

# Alternativt: random transition hver gang
# TRANSITIONS=("fade" "wipe" "grow" "wave")
# RANDOM_TRANSITION=${TRANSITIONS[$RANDOM % ${#TRANSITIONS[@]}]}
# swww img "$WALLPAPER_DIR/$WALLPAPER_FILE" --transition-type $RANDOM_TRANSITION
