#!/bin/bash
# ===========================================
# Script: harvest-fapolicyd-deny.sh
# Purpose: Harvest denied executables from fapolicyd debug-deny
#          and create individual rules files per binary.
#          Extracts UID/GID and SELinux context when available.
# Compatible: RHEL 9.7 / latest fapolicyd
# ===========================================

set -euo pipefail

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] Please run as root."
    exit 1
fi

# Directories and temp files
OUTPUT_FILE="/tmp/fapolicyd.debug-deny"
RULES_DIR="/etc/fapolicyd/rules.d"

# Ensure rules directory exists
mkdir -p "$RULES_DIR"

echo "[*] Running fapolicyd --debug-deny..."
fapolicyd --debug-deny 2> "$OUTPUT_FILE"

# Process each DENY line safely without creating a subshell
while IFS= read -r line; do
    # Extract path (second field)
    binary_path=$(awk '{print $2}' <<< "$line")

    # Skip if empty or not an absolute path
    if [[ -z "$binary_path" || "$binary_path" != /* ]]; then
        continue
    fi

    # Sanitize filename for rule file
    binary_name=$(basename "$binary_path" | tr -c '[:alnum:]_' '_')
    rule_file="${RULES_DIR}/99-${binary_name}.rules"

    # Skip if rule file exists
    if [[ -f "$rule_file" ]]; then
        echo "[*] Rule file for $binary_path already exists. Skipping."
        continue
    fi

    # Try to get UID, GID, SELinux context
    if [[ -e "$binary_path" ]]; then
        uid=$(stat -c "%u" "$binary_path")
        gid=$(stat -c "%g" "$binary_path")
        selinux_context=$(stat -c "%C" "$binary_path")
    else
        uid=0
        gid=0
        selinux_context="system_u:object_r:bin_t:s0"
    fi

    echo "[*] Creating rule file for $binary_path -> $rule_file"
    {
        echo "# Auto-generated fapolicyd rule for denied binary: $binary_path"
        echo "# Generated on $(date)"
        echo "allow perm=any uid=${uid} gid=${gid} context=${selinux_context} : path=$binary_path"
    } > "$rule_file"

    chmod 644 "$rule_file"
done < <(grep 'DENY' "$OUTPUT_FILE")

echo "[*] Done. Reload fapolicyd to apply rules:"
echo "    systemctl reload fapolicyd"
