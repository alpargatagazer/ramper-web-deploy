#!/usr/bin/env bash
# Orchestra Management Script
# Simplifies deployment, teardown, and Dockcheck automation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Load environment variables
if [ -f .env ]; then
    set -a
    source .env
    set +a
fi

DOCKCHECK_URL="https://raw.githubusercontent.com/mag37/dockcheck/main/dockcheck.sh"
DOCKCHECK_PATH="$SCRIPT_DIR/dockcheck.sh"
REGCTL_URL="https://github.com/regclient/regclient/releases/latest/download/regctl-linux-amd64"
SERVICE_NAME="orchestra-updater"

usage() {
    echo "Usage: $0 {up|down|status|logs|logs-update|install-dockcheck|update-dockcheck|setup-daemon}"
    echo ""
    echo "Orchestra Commands:"
    echo "  up                : Pull latest images and start the orchestra"
    echo "  down              : Stop and remove the orchestra containers"
    echo "  status            : Show status of the orchestra"
    echo "  logs              : Show logs for all services (via Docker)"
    echo "  logs-update       : Show logs for the auto-update daemon (via journalctl)"
    echo ""
    echo "Dockcheck Commands:"
    echo "  install-dockcheck : Download dockcheck.sh and required dependencies (regctl)"
    echo "  update-dockcheck  : Self-update the dockcheck.sh script"
    echo "  setup-daemon      : Create and enable a systemd timer for auto-updates"
}

case "$1" in
    up)
        echo "🚀 Starting Ramper Orchestra..."
        docker compose pull
        docker compose up -d --remove-orphans
        echo "✅ Orchestra is up."
        ;;
    down)
        echo "🛑 Stopping Ramper Orchestra..."
        docker compose down
        echo "✅ Orchestra stopped."
        ;;
    status)
        docker compose ps
        ;;
    logs)
        docker compose logs -f
        ;;
    logs-update)
        echo "📜 Showing logs for $SERVICE_NAME..."
        journalctl -u "$SERVICE_NAME" -f
        ;;
    install-dockcheck)
        # 1. Download Dockcheck
        if [ ! -f "$DOCKCHECK_PATH" ]; then
            echo "📥 Downloading Dockcheck..."
            curl -fsSL "$DOCKCHECK_URL" -o "$DOCKCHECK_PATH"
            chmod +x "$DOCKCHECK_PATH"
            echo "✅ Dockcheck installed at $DOCKCHECK_PATH"
        else
            echo "ℹ️ Dockcheck is already installed."
        fi

        # 2. Download regctl (required for remote checks)
        if ! command -v regctl &> /dev/null; then
            echo "📥 Downloading regctl dependency..."
            sudo curl -L "$REGCTL_URL" -o /usr/local/bin/regctl
            sudo chmod +x /usr/local/bin/regctl
            echo "✅ regctl installed at /usr/local/bin/regctl"
        else
            echo "ℹ️ regctl is already installed."
        fi
        ;;
    update-dockcheck)
        echo "🔄 Updating Dockcheck..."
        curl -fsSL "$DOCKCHECK_URL" -o "$DOCKCHECK_PATH"
        chmod +x "$DOCKCHECK_PATH"
        echo "✅ Dockcheck updated."
        ;;
    setup-daemon)
        if [ ! -f "$DOCKCHECK_PATH" ]; then
            echo "❌ Dockcheck not found. Please run '$0 install-dockcheck' first."
            exit 1
        fi
        
        echo "⚙️ Setting up systemd timer for auto-updates..."
        
        # We use a OneShot service + Timer for better management
        cat <<EOF | sudo tee /etc/systemd/system/${SERVICE_NAME}.service
[Unit]
Description=Ramper Orchestra Auto-Updater
After=network.target docker.service

[Service]
Type=oneshot
User=root
WorkingDirectory=$SCRIPT_DIR
# Ensure docker and other binaries are in PATH
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=$DOCKCHECK_PATH -u -n -r
EOF

        cat <<EOF | sudo tee /etc/systemd/system/${SERVICE_NAME}.timer
[Unit]
Description=Ramper Orchestra Auto-Updater Timer

[Timer]
OnBootSec=5min
OnUnitActiveSec=15min
Persistent=true

[Install]
WantedBy=timers.target
EOF

        sudo systemctl daemon-reload
        sudo systemctl enable --now ${SERVICE_NAME}.timer
        
        echo "✅ Timer '${SERVICE_NAME}' is active (every 15 min). Check with: systemctl list-timers"
        echo "ℹ️ You can view update logs with: $0 logs-update"
        ;;
    *)
        usage
        exit 1
        ;;
esac
