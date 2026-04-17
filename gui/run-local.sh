#!/usr/bin/env bash
# Run the GUI natively on the Pi with the same config as the Docker container.
# Usage: cd gui && ./run-local.sh
#
# Prerequisites:
#   go build -o mowglinext && cd web && yarn && yarn build && cd ..

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "$SCRIPT_DIR/../install" && pwd)"

# ── Check dependencies ────────────────────────────────────────────────────────

missing=()
command -v go   >/dev/null 2>&1 || missing+=(go)
command -v node >/dev/null 2>&1 || missing+=(node)
command -v yarn >/dev/null 2>&1 || missing+=(yarn)

if [ ${#missing[@]} -gt 0 ]; then
  echo "Missing dependencies: ${missing[*]}"
  echo -n "Install them? [Y/n]: "
  read -r answer
  if [[ "${answer,,}" != "n" ]]; then
    sudo apt update
    # Install in order: go, node, then yarn (yarn needs node/corepack)
    for dep in go node yarn; do
      # Skip if not in the missing list
      printf '%s\n' "${missing[@]}" | grep -qx "$dep" || continue
      case "$dep" in
        go)
          echo "Installing Go..."
          sudo apt install -y golang
          ;;
        node)
          echo "Installing Node.js..."
          curl -fsSL https://deb.nodesource.com/setup_22.x | sudo bash -
          sudo apt install -y nodejs
          ;;
        yarn)
          echo "Installing Yarn..."
          sudo corepack enable
          ;;
      esac
    done
  else
    echo "Aborting — missing: ${missing[*]}"
    exit 1
  fi
fi

# ── Stop Docker GUI if running ───────────────────────────────────────────────
# Stop the Docker GUI container if running (same port conflict)
if docker inspect -f '{{.State.Status}}' mowgli-gui 2>/dev/null | grep -q running; then
  echo "mowgli-gui container is running (port 80 conflict)."
  echo -n "Stop it? [Y/n]: "
  read -r answer
  if [[ "${answer,,}" != "n" ]]; then
    docker stop mowgli-gui >/dev/null
    echo "Stopped mowgli-gui"
  else
    echo "Aborting — can't bind to the same port."
    exit 1
  fi
fi

export FOXGLOVE_URL="${FOXGLOVE_URL:-ws://localhost:8765}"
export MOWER_CONFIG_FILE="${MOWER_CONFIG_FILE:-$INSTALL_DIR/config/om/mower_config.sh}"
export MOWER_YAML_CONFIG_FILE="${MOWER_YAML_CONFIG_FILE:-$INSTALL_DIR/config/mowgli/mowgli_robot.yaml}"
export DB_PATH="${DB_PATH:-$SCRIPT_DIR/.db}"
export WEB_DIR="${WEB_DIR:-$SCRIPT_DIR/web/dist}"
export DOCKER_HOST="${DOCKER_HOST:-unix:///var/run/docker.sock}"

# Build if binary is missing or older than source
if [ ! -f "$SCRIPT_DIR/mowglinext" ] || \
   [ "$(find "$SCRIPT_DIR" -name '*.go' -newer "$SCRIPT_DIR/mowglinext" 2>/dev/null | head -1)" ]; then
  echo "Building Go binary..."
  (cd "$SCRIPT_DIR" && go build -o mowglinext)
fi

# Build frontend if dist is missing
if [ ! -d "$SCRIPT_DIR/web/dist" ]; then
  echo "Building frontend..."
  (cd "$SCRIPT_DIR/web" && yarn && yarn build)
fi

mkdir -p "$DB_PATH"

echo "Starting mowglinext GUI..."
echo "  FOXGLOVE_URL:          $FOXGLOVE_URL"
echo "  MOWER_CONFIG_FILE:     $MOWER_CONFIG_FILE"
echo "  MOWER_YAML_CONFIG_FILE: $MOWER_YAML_CONFIG_FILE"
echo "  DB_PATH:               $DB_PATH"
echo "  WEB_DIR:               $WEB_DIR"
echo ""

"$SCRIPT_DIR/mowglinext"
