#!/usr/bin/env bash
chmod +x scripts/*.sh 2>/dev/null || true
echo "EasyVbox scripts ready."
read -rp "Install helper tools (zenity whiptail jq)? [Y/n] " a
if [[ "${a:-Y}" =~ ^[Yy] ]]; then
  command -v apt-get && sudo apt-get install -y zenity whiptail jq
  command -v dnf && sudo dnf install -y zenity newt jq
fi
echo "Run: ./scripts/create-vm.sh --list-presets"
