#!/bin/bash

# Consolidated Touchpad Manager
# - Disables touchpad when external mouse is connected
# - Disables touchpad while typing (only when mouse is NOT connected)

# Configuration
TOUCHPAD_DEVICE="ASUS Zenbook Duo Keyboard Touchpad"
KEYBOARD_DEVICE="ASUS Zenbook Duo Keyboard"
MOUSE_USB_ID="1c4f:0034"  # SiGma Micro XM102K Optical Wheel Mouse
MOUSE_CHECK_INTERVAL=1  # seconds between mouse connection checks
DISABLE_DURATION=50  # Milliseconds to keep touchpad disabled after last keystroke

echo "Touchpad Manager - Consolidated Script"
echo "======================================"
echo "Touchpad: $TOUCHPAD_DEVICE"
echo "Keyboard: $KEYBOARD_DEVICE"
echo "Mouse USB ID: $MOUSE_USB_ID"
echo "Mouse check interval: ${MOUSE_CHECK_INTERVAL}s"
echo "Typing disable duration: ${DISABLE_DURATION}ms"
echo ""
echo "Press Ctrl+C to stop"
echo ""

# Get keyboard event device
KEYBOARD_EVENT=$(libinput list-devices 2>/dev/null | grep -A 20 "^Device:.*$KEYBOARD_DEVICE$" | grep "Kernel:" | awk '{print $2}' | head -1)

if [ -z "$KEYBOARD_EVENT" ]; then
    echo "Warning: Could not find keyboard event device '$KEYBOARD_DEVICE'"
    echo "Typing detection will be disabled."
    KEYBOARD_EVENT=""
fi

# Function to check if mouse is connected
is_mouse_connected() {
    lsusb | grep -q "$MOUSE_USB_ID"
    return $?
}

# Function to disable touchpad via KDE DBus
disable_touchpad() {
    TOUCHPAD_EVENT=$(libinput list-devices 2>/dev/null | grep -A 20 "^Device:.*$TOUCHPAD_DEVICE$" | grep "Kernel:" | awk '{print $2}' | grep -oP 'event\K[0-9]+')
    
    if [ -n "$TOUCHPAD_EVENT" ]; then
        busctl --user set-property org.kde.KWin /org/kde/KWin/InputDevice/event${TOUCHPAD_EVENT} org.kde.KWin.InputDevice enabled b false 2>/dev/null
    fi
}

# Function to enable touchpad via KDE DBus
enable_touchpad() {
    TOUCHPAD_EVENT=$(libinput list-devices 2>/dev/null | grep -A 20 "^Device:.*$TOUCHPAD_DEVICE$" | grep "Kernel:" | awk '{print $2}' | grep -oP 'event\K[0-9]+')
    
    if [ -n "$TOUCHPAD_EVENT" ]; then
        busctl --user set-property org.kde.KWin /org/kde/KWin/InputDevice/event${TOUCHPAD_EVENT} org.kde.KWin.InputDevice enabled b true 2>/dev/null
    fi
}

# State files
TIMER_FILE="/tmp/touchpad_typing_timer_$$"
DISABLED_FLAG="/tmp/touchpad_disabled_$$"

# Process IDs
TYPING_MONITOR_PID=""
TYPING_TIMER_PID=""

# Cleanup on exit
cleanup() {
    echo ""
    echo "Cleaning up..."
    
    # Kill child processes
    [ -n "$TYPING_MONITOR_PID" ] && kill $TYPING_MONITOR_PID 2>/dev/null
    [ -n "$TYPING_TIMER_PID" ] && kill $TYPING_TIMER_PID 2>/dev/null
    
    # Re-enable touchpad
    enable_touchpad
    
    # Remove temp files
    rm -f "$TIMER_FILE" "$DISABLED_FLAG"
    
    echo "Touchpad re-enabled. Exiting."
    exit 0
}

trap cleanup SIGINT SIGTERM EXIT

# Function to start typing detection
start_typing_detection() {
    if [ -z "$KEYBOARD_EVENT" ]; then
        return
    fi
    
    # Stop any existing typing detection
    stop_typing_detection
    
    echo "  Starting typing detection..."
    
    # Background process to re-enable touchpad after timeout (EXACT COPY from disable-touchpad-typing.sh)
    (
        while true; do
            if [ -f "$TIMER_FILE" ]; then
                LAST_TIME=$(cat "$TIMER_FILE")
                CURRENT_TIME=$(date +%s%3N)  # milliseconds
                ELAPSED=$((CURRENT_TIME - LAST_TIME))
                
                if [ $ELAPSED -ge $((DISABLE_DURATION)) ]; then
                    enable_touchpad
                    rm -f "$DISABLED_FLAG"  # Clear the disabled flag
                    rm -f "$TIMER_FILE"
                fi
            fi
            sleep 0.05
        done
    ) &
    TYPING_TIMER_PID=$!
    
    # Monitor keyboard events (EXACT COPY from disable-touchpad-typing.sh)
    if command -v evtest >/dev/null 2>&1; then
        echo "  Using evtest to monitor keyboard..."
        (
            stdbuf -oL evtest "$KEYBOARD_EVENT" 2>/dev/null | while read line; do
                if echo "$line" | grep -q "type 1.*code.*value 1"; then
                    if [ ! -f "$DISABLED_FLAG" ]; then  # Check if flag file exists
                        disable_touchpad
                        touch "$DISABLED_FLAG"  # Create flag file
                    fi
                    date +%s%3N > "$TIMER_FILE"
                fi
            done
        ) &
        TYPING_MONITOR_PID=$!
    else
        echo "  evtest not found, trying direct event reading..."
        # Fall back to hexdump for reading raw events
        (
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
        ) &
        TYPING_MONITOR_PID=$!
    fi
}

# Function to stop typing detection
stop_typing_detection() {
    if [ -n "$TYPING_MONITOR_PID" ]; then
        kill $TYPING_MONITOR_PID 2>/dev/null
        TYPING_MONITOR_PID=""
    fi
    
    if [ -n "$TYPING_TIMER_PID" ]; then
        kill $TYPING_TIMER_PID 2>/dev/null
        TYPING_TIMER_PID=""
    fi
    
    # Clean up typing detection files
    rm -f "$TIMER_FILE" "$DISABLED_FLAG"
}

# Initialize state
PREVIOUS_MOUSE_STATE=""

# Main loop - check for mouse connection
while true; do
    if is_mouse_connected; then
        CURRENT_MOUSE_STATE="connected"
        
        if [ "$PREVIOUS_MOUSE_STATE" != "connected" ]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Mouse connected"
            
            # Stop typing detection
            stop_typing_detection
            echo "  Typing detection stopped"
            
            # Disable touchpad
            disable_touchpad
            echo "  ✓ Touchpad disabled (mouse mode)"
        fi
    else
        CURRENT_MOUSE_STATE="disconnected"
        
        if [ "$PREVIOUS_MOUSE_STATE" != "disconnected" ] && [ -n "$PREVIOUS_MOUSE_STATE" ]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Mouse disconnected"
            
            # Enable touchpad
            enable_touchpad
            echo "  ✓ Touchpad enabled"
            
            # Start typing detection
            start_typing_detection
        fi
        
        # Ensure typing detection is running when no mouse is connected
        if [ -z "$TYPING_MONITOR_PID" ] && [ -n "$KEYBOARD_EVENT" ]; then
            start_typing_detection
        fi
    fi
    
    PREVIOUS_MOUSE_STATE="$CURRENT_MOUSE_STATE"
    sleep $MOUSE_CHECK_INTERVAL
done
