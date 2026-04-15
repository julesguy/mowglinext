#!/usr/bin/env bash
# =============================================================================
# mowglinext — Clean / Reset Script
#
# Removes everything the installer created so the machine is clean for a
# fresh install.  The git repo itself is kept on the current branch.
#
# Usage:  bash install/clean.sh [--yes]
#         --yes  skip all confirmation prompts
# =============================================================================

set -euo pipefail

# ── Colours & helpers ─────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

info()  { echo -e "  ${GREEN}✓${NC}  $*"; }
warn()  { echo -e "  ${YELLOW}!${NC}  $*"; }
skip()  { echo -e "  ${DIM}-${NC}  $* ${DIM}(not found)${NC}"; }
step()  { echo -e "\n${CYAN}${BOLD}── $* ──${NC}"; }

AUTO_YES=false
[[ "${1:-}" == "--yes" ]] && AUTO_YES=true

confirm() {
  if $AUTO_YES; then return 0; fi
  local answer
  echo -en "${BOLD}$1 [y/N]:${NC} "
  read -r answer
  [[ "${answer,,}" == "y" ]]
}

if [ "$(id -u)" -ne 0 ]; then
  SUDO="sudo"
else
  SUDO=""
fi

# Docker sudo — same logic as the installer
if id -nG | grep -qw docker 2>/dev/null; then
  DOCKER_SUDO=""
else
  DOCKER_SUDO="$SUDO"
fi

# ── Paths ─────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL_DIR="${SCRIPT_DIR}"

echo ""
echo -e "${RED}${BOLD}══ Mowgli Uninstall ══${NC}"
echo ""
echo "This will remove all Mowgli artifacts from the system,"
echo "including Docker, the repo at ${REPO_DIR}, and all generated configs."
echo ""

if ! confirm "Continue?"; then
  echo "Aborted."
  exit 0
fi

# ── 1. Docker containers, images, volumes ─────────────────────────────────────

step "Docker stack"

if command -v docker &>/dev/null; then
  if [ -f "$INSTALL_DIR/docker-compose.yaml" ]; then
    echo -e "  ${DIM}Stopping and removing containers...${NC}"
    $DOCKER_SUDO docker compose -f "$INSTALL_DIR/docker-compose.yaml" \
      --env-file "$INSTALL_DIR/.env" down --remove-orphans 2>/dev/null || true
    info "Containers stopped and removed"
  else
    skip "docker-compose.yaml"
  fi

  # Nuke everything: all containers, all images, all volumes, all networks
  echo -e "  ${DIM}Removing ALL containers...${NC}"
  $DOCKER_SUDO docker container prune -f 2>/dev/null || true
  # Kill any stragglers still running
  running=$($DOCKER_SUDO docker ps -q 2>/dev/null || true)
  if [ -n "$running" ]; then
    echo "$running" | xargs $DOCKER_SUDO docker rm -f 2>/dev/null || true
  fi
  info "All containers removed"

  echo -e "  ${DIM}Removing ALL images...${NC}"
  all_images=$($DOCKER_SUDO docker images -q 2>/dev/null || true)
  if [ -n "$all_images" ]; then
    echo "$all_images" | xargs $DOCKER_SUDO docker rmi -f 2>/dev/null || true
    info "All images removed"
  else
    skip "No images"
  fi

  echo -e "  ${DIM}Removing ALL volumes...${NC}"
  $DOCKER_SUDO docker volume prune -af 2>/dev/null || true
  info "All volumes removed"

  echo -e "  ${DIM}Removing ALL networks...${NC}"
  $DOCKER_SUDO docker network prune -f 2>/dev/null || true
  info "All networks removed"

  # Remove Docker itself
  step "Docker engine"
  echo -e "  ${DIM}Purging Docker packages...${NC}"
  $SUDO apt purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null || true
  $SUDO apt autoremove -y 2>/dev/null || true
  info "Docker packages purged"

  # Clean up Docker data dirs
  if [ -d /var/lib/docker ]; then
    $SUDO rm -rf /var/lib/docker
    info "Removed /var/lib/docker"
  fi
  if [ -d /var/lib/containerd ]; then
    $SUDO rm -rf /var/lib/containerd
    info "Removed /var/lib/containerd"
  fi
  if [ -f /etc/docker/daemon.json ]; then
    $SUDO rm -f /etc/docker/daemon.json
    info "Removed /etc/docker/daemon.json"
  fi
  if [ -d "$HOME/.docker" ]; then
    rm -rf "$HOME/.docker"
    info "Removed ~/.docker"
  fi

  # Remove docker group membership
  if groups "$USER" | grep -qw docker 2>/dev/null; then
    $SUDO gpasswd -d "$USER" docker 2>/dev/null || true
    info "Removed $USER from docker group"
  fi
else
  skip "Docker not installed"
fi

# ── 2. Helper scripts in /usr/local/bin ───────────────────────────────────────

step "Helper scripts"

HELPERS=(
  mowgli-up mowgli-down mowgli-restart mowgli-logs mowgli-ps
  mowgli-pull mowgli-check mowgli-gps-logs mowgli-lidar-logs
  mowgli-shell mowgli-status dockermgr
)

for h in "${HELPERS[@]}"; do
  if [ -f "/usr/local/bin/$h" ]; then
    $SUDO rm -f "/usr/local/bin/$h"
    info "Removed /usr/local/bin/$h"
  fi
done

# ── 3. MOTD ──────────────────────────────────────────────────────────────────

step "MOTD"

if [ -f /etc/profile.d/mowgli-motd.sh ]; then
  $SUDO rm -f /etc/profile.d/mowgli-motd.sh
  info "Removed /etc/profile.d/mowgli-motd.sh"
else
  skip "/etc/profile.d/mowgli-motd.sh"
fi

# ── 4. Udev rules ────────────────────────────────────────────────────────────

step "Udev rules"

if [ -f /etc/udev/rules.d/50-mowgli.rules ]; then
  $SUDO rm -f /etc/udev/rules.d/50-mowgli.rules
  $SUDO udevadm control --reload-rules 2>/dev/null || true
  $SUDO udevadm trigger 2>/dev/null || true
  info "Removed /etc/udev/rules.d/50-mowgli.rules"
else
  skip "/etc/udev/rules.d/50-mowgli.rules"
fi

# ── 5. rc.local & systemd service ────────────────────────────────────────────

step "rc.local"

if [ -f /etc/rc.local ] && grep -q "MOWGLI_UART_INIT" /etc/rc.local 2>/dev/null; then
  if [ -f /etc/rc.local.bak ]; then
    $SUDO mv /etc/rc.local.bak /etc/rc.local
    info "Restored /etc/rc.local from backup"
  else
    $SUDO rm -f /etc/rc.local
    info "Removed /etc/rc.local (no backup to restore)"
  fi
else
  skip "/etc/rc.local (not ours)"
fi

if [ -f /etc/systemd/system/rc-local.service ]; then
  $SUDO systemctl disable --now rc-local.service 2>/dev/null || true
  $SUDO rm -f /etc/systemd/system/rc-local.service
  $SUDO systemctl daemon-reload 2>/dev/null || true
  info "Removed rc-local.service"
else
  skip "rc-local.service"
fi

# ── 6. APT pin ───────────────────────────────────────────────────────────────

step "APT configuration"

if [ -f /etc/apt/apt.conf.d/99defaultrelease ]; then
  $SUDO rm -f /etc/apt/apt.conf.d/99defaultrelease
  info "Removed APT release pin"
else
  skip "/etc/apt/apt.conf.d/99defaultrelease"
fi

# ── 7. lazydocker (installed to ~/.local/bin by upstream script) ──────────────

step "Optional tools"

if [ -f "$HOME/.local/bin/lazydocker" ]; then
  rm -f "$HOME/.local/bin/lazydocker"
  info "Removed ~/.local/bin/lazydocker"
else
  skip "lazydocker"
fi

# Not removing apt packages (mc, ranger, htop, ctop, etc.) — they're common
# system tools the user might want to keep.
echo -e "  ${DIM}APT packages (mc, ranger, htop, etc.) left in place${NC}"

# ── 8. Install-generated files ───────────────────────────────────────────────

step "Install artifacts"

generated_files=(
  "$INSTALL_DIR/.env"
  "$INSTALL_DIR/.preset"
  "$INSTALL_DIR/docker-compose.yaml"
)

for f in "${generated_files[@]}"; do
  if [ -f "$f" ]; then
    rm -f "$f"
    info "Removed $f"
  fi
done

generated_dirs=(
  "$INSTALL_DIR/config"
  "$INSTALL_DIR/logs"
)

for d in "${generated_dirs[@]}"; do
  if [ -d "$d" ]; then
    rm -rf "$d"
    info "Removed $d/"
  fi
done

# ── 9. Boot config (informational only) ──────────────────────────────────────

step "Boot configuration"

boot_config=""
for f in /boot/firmware/config.txt /boot/config.txt; do
  if [ -f "$f" ]; then boot_config="$f"; break; fi
done

if [ -n "$boot_config" ] && grep -q "dtoverlay=uart" "$boot_config" 2>/dev/null; then
  warn "UART overlays in $boot_config left in place (manual removal if needed):"
  grep "dtoverlay=" "$boot_config" | while read -r line; do
    echo -e "       ${DIM}$line${NC}"
  done
  if grep -q "disable-bt" "$boot_config" 2>/dev/null; then
    echo -e "       ${DIM}dtoverlay=disable-bt${NC}"
  fi
  echo -e "  ${DIM}Edit manually: sudo nano $boot_config${NC}"
else
  skip "No UART overlays found in boot config"
fi

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo -e "${GREEN}${BOLD}══ Clean complete ══${NC}"
echo ""
if [ -n "$boot_config" ] && grep -q "dtoverlay=uart" "$boot_config" 2>/dev/null; then
  echo "What's left:"
  echo "  - UART overlays in $boot_config (see above)"
  echo ""
fi

# ── 10. Remove repository (must be last) ─────────────────────────────────────
# The script is already loaded in memory by bash, so rm is safe.

step "Repository"

if [ -d "$REPO_DIR" ]; then
  rm -rf "$REPO_DIR"
  info "Removed $REPO_DIR"
else
  skip "$REPO_DIR"
fi

echo ""
echo "To reinstall:"
echo "  curl -fsSL https://raw.githubusercontent.com/Mowglifrenchtouch/mowglinext/main/install/mowglinext.sh | bash"
