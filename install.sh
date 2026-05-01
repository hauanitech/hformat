#!/bin/bash

set -euo pipefail

SCRIPT_NAME="hformat"
SOURCE="$(cd "$(dirname "$0")" && pwd)/hformat.sh"
INSTALL_DIR="${HOME}/.local/bin"
DEST="${INSTALL_DIR}/${SCRIPT_NAME}"

if [ "${1:-}" = "--uninstall" ]; then
    if [ -f "$DEST" ]; then
        rm "$DEST"
        echo "${SCRIPT_NAME} removed from ${DEST}"
    else
        echo "${SCRIPT_NAME} is not installed."
        exit 1
    fi
    exit 0
fi

if [ ! -f "$SOURCE" ]; then
    echo "Error: hformat.sh not found in $(dirname "$SOURCE")"
    exit 1
fi

mkdir -p "$INSTALL_DIR"

cp "$SOURCE" "$DEST"
chmod +x "$DEST"

if ! echo "$PATH" | grep -q "${INSTALL_DIR}"; then
    echo "Warning: ${INSTALL_DIR} is not in your PATH."
    echo "Add this line to your shell profile (~/.bashrc or ~/.zshrc):"
    echo ""
    echo "  export PATH=\"\${HOME}/.local/bin:\${PATH}\""
    echo ""
fi

echo "${SCRIPT_NAME} installed to ${DEST}"
