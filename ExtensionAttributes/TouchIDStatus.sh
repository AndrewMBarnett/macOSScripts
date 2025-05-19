#!/bin/bash

touchIDStatus="Unknown"
fingerCount="0"

# Get the logged-in user and UID
loggedInUser=$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }')
loggedInUID=$(id -u "$loggedInUser" 2>/dev/null)

# Check if Mac supports Touch ID (Apple Silicon or T2)
isAppleSilicon=$(sysctl -n machdep.cpu.brand_string | grep -c "Apple")
hasT2Chip=$(system_profiler SPiBridgeDataType 2>/dev/null | grep -c "Apple T2")

if [[ "$isAppleSilicon" -eq 0 && "$hasT2Chip" -eq 0 ]]; then
    echo "<result>Not Supported</result>"
    exit 0
fi

# Function to run command as the user
runAsUser() {
    if [[ "$loggedInUID" -gt 0 ]]; then
        launchctl asuser "$loggedInUID" sudo -u "$loggedInUser" "$@"
    fi
}

# Check for bioutil
if command -v bioutil &>/dev/null; then

    # Get fingerprint count
    fingerCount=$(runAsUser bioutil -c 2>/dev/null | grep -oE 'User [0-9]+:[[:space:]]([0-9]+)' | awk -F':[[:space:]]' '{print $2}')

    if [[ -z "$fingerCount" ]]; then
        if runAsUser bioutil -c 2>/dev/null | grep -q "There are no biometric templates in the system."; then
            fingerCount="0"
        fi
    fi

    unlockEnabled=$(runAsUser bioutil -r 2>/dev/null | awk -F ': ' '/Effective biometrics for unlock/ {print $2}')

    if [[ "$fingerCount" -gt 0 && "$unlockEnabled" == "1" ]]; then
        touchIDStatus="Enabled"
    elif [[ "$unlockEnabled" == "0" ]]; then
        touchIDStatus="Disabled by Policy"
    elif [[ "$fingerCount" -eq 0 ]]; then
        touchIDStatus="No Fingers Enrolled"
    else
        touchIDStatus="Disabled"
    fi

# Fallback if bioutil is unavailable
elif [[ -f /Library/Preferences/com.apple.BiometricKit.plist ]]; then
    fingerCount=$(/usr/libexec/PlistBuddy -c "Print BioEnrollment" /Library/Preferences/com.apple.BiometricKit.plist 2>/dev/null | grep -c "Touch ID")

    if [[ "$fingerCount" -gt 0 ]]; then
        touchIDStatus="Enabled (fallback)"
    else
        touchIDStatus="Disabled (fallback)"
    fi
else
    touchIDStatus="Not Available"
fi

echo "<result>$touchIDStatus | $fingerCount fingerprint(s) | User: $loggedInUser</result>"
