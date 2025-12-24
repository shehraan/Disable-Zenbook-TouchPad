#!/bin/bash

# Disable touchpad while typing script for KDE Wayland
# Uses evtest to monitor keyboard and KDE DBus to control touchpad

# Configuration
TOUCHPAD_DEVICE="ASUS Zenbook Duo Keyboard Touchpad"
KEYBOARD_DEVICE="ASUS Zenbook Duo Keyboard"
DISABLE_DURATION=1  # seconds to keep touchpad disabled after last keystroke

# Get keyboard event device
KEYBOARD_EVENT=$(libinput list-devices 2>/dev/null | grep -A 20 "^Device:.*$KEYBOARD_DEVICE$" | grep "Kernel:" | awk '{print $2}' | head -1)

if [ -z "$KEYBOARD_EVENT" ]; then
    echo "Error: Could not find keyboard event device '$KEYBOARD_DEVICE'"
    echo "Available devices:"
    libinput list-devices 2>/dev/null | grep "Device:" || echo "libinput not available"
    exit 1
fi

echo "Found keyboard device: $KEYBOARD_DEVICE"
echo "Monitoring keyboard: $KEYBOARD_EVENT"
echo "Disable duration: ${DISABLE_DURATION}s"
echo "Press Ctrl+C to stop"

# Function to disable touchpad via KDE DBus
disable_touchpad() {
    # Get the touchpad event number dynamically
    TOUCHPAD_EVENT=$(libinput list-devices 2>/dev/null | grep -A 20 "^Device:.*$TOUCHPAD_DEVICE$" | grep "Kernel:" | awk '{print $2}' | grep -oP 'event\K[0-9]+')
    
    if [ -n "$TOUCHPAD_EVENT" ]; then
        # Use the correct KWin DBus path format
        busctl --user set-property org.kde.KWin /org/kde/KWin/InputDevice/event${TOUCHPAD_EVENT} org.kde.KWin.InputDevice enabled b false 2>/dev/null
    fi
}

# Function to enable touchpad via KDE DBus
enable_touchpad() {
    # Get the touchpad event number dynamically
    TOUCHPAD_EVENT=$(libinput list-devices 2>/dev/null | grep -A 20 "^Device:.*$TOUCHPAD_DEVICE$" | grep "Kernel:" | awk '{print $2}' | grep -oP 'event\K[0-9]+')
    
    if [ -n "$TOUCHPAD_EVENT" ]; then
        # Use the correct KWin DBus path format
        busctl --user set-property org.kde.KWin /org/kde/KWin/InputDevice/event${TOUCHPAD_EVENT} org.kde.KWin.InputDevice enabled b true 2>/dev/null
    fi
}

# Timer file to track last keystroke
TIMER_FILE="/tmp/touchpad_typing_timer_$$"
DISABLED_FLAG="/tmp/touchpad_disabled_$$"  # File-based flag instead of variable

# Cleanup on exit
cleanup() {
    enable_touchpad
    rm -f "$TIMER_FILE" "$DISABLED_FLAG"
    kill $TIMER_PID 2>/dev/null
    exit 0
}

trap cleanup SIGINT SIGTERM EXIT

# Background process to re-enable touchpad after timeout
(
    while true; do
        if [ -f "$TIMER_FILE" ]; then
            LAST_TIME=$(cat "$TIMER_FILE")
            CURRENT_TIME=$(date +%s%3N)  # milliseconds
            ELAPSED=$((CURRENT_TIME - LAST_TIME))
            
            if [ $ELAPSED -ge $((DISABLE_DURATION * 1000)) ]; then
                enable_touchpad
                rm -f "$DISABLED_FLAG"  # Clear the disabled flag
                rm -f "$TIMER_FILE"
            fi
        fi
        sleep 0.05
    done
) &
TIMER_PID=$!

if command -v evtest >/dev/null 2>&1; then
    echo "Using evtest to monitor keyboard..."
    stdbuf -oL evtest "$KEYBOARD_EVENT" 2>/dev/null | while read line; do
        if echo "$line" | grep -q "type 1.*code.*value 1"; then
            if [ ! -f "$DISABLED_FLAG" ]; then  # Check if flag file exists
                disable_touchpad
                touch "$DISABLED_FLAG"  # Create flag file
            fi
            date +%s%3N > "$TIMER_FILE"
        fi
    done
else
    echo "evtest not found, trying direct event reading..."
    # Fall back to hexdump for reading raw events
    stdbuf -oL hexdump -v -e '1/1 "%02x"' "$KEYBOARD_EVENT" 2>/dev/null | while read -n 32 event; do
        # Very basic event parsing - look for key press patterns
        # Event structure: timestamp(16) + type(4) + code(4) + value(8)
        if [ -n "$event" ]; then
            if [ ! -f "$DISABLED_FLAG" ]; then  # Check if flag file exists
                disable_touchpad
                touch "$DISABLED_FLAG"  # Create flag file
            fi
            date +%s%3N > "$TIMER_FILE"
        fi
    done
fi
