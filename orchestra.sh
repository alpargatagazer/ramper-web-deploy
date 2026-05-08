#!/usr/bin/env bash
# Orchestra Management Script
# Simplifies deployment, teardown, and Dockcheck automation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Load environment variables
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

DOCKCHECK_URL="https://raw.githubusercontent.com/mag37/dockcheck/main/dockcheck.sh"
DOCKCHECK_PATH="$SCRIPT_DIR/dockcheck.sh"
SERVICE_NAME="orchestra-updater"

usage() {
    echo "Usage: $0 {up|down|status|logs|install-dockcheck|update-dockcheck|setup-daemon}"
    echo ""
    echo "Orchestra Commands:"
    echo "  up                : Pull latest images and start the orchestra"
    echo "  down              : Stop and remove the orchestra containers"
    echo "  status            : Show status of the orchestra"
    echo "  logs              : Show logs for all services"
    echo ""
    echo "Dockcheck Commands:"
    echo "  install-dockcheck : Download dockcheck.sh if not present"
    echo "  update-dockcheck  : Self-update the dockcheck.sh script"
    echo "  setup-daemon      : Create and enable a systemd service for auto-updates"
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
    install-dockcheck)
        if [ ! -f "$DOCKCHECK_PATH" ]; then
            echo "📥 Downloading Dockcheck..."
            curl -fsSL "$DOCKCHECK_URL" -o "$DOCKCHECK_PATH"
            chmod +x "$DOCKCHECK_PATH"
            echo "✅ Dockcheck installed at $DOCKCHECK_PATH"
        else
            echo "ℹ️ Dockcheck is already installed."
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
        
        echo "⚙️ Setting up systemd daemon for auto-updates..."
        
        cat <<EOF | sudo tee /etc/systemd/system/${SERVICE_NAME}.service
[Unit]
Description=Ramper Orchestra Auto-Updater (Dockcheck)
After=docker.service

[Service]
Type=simple
WorkingDirectory=$SCRIPT_DIR
ExecStart=$DOCKCHECK_PATH -u -n -r
# Restart every 1 hour (3600 seconds)
Restart=always
RestartSec=3600

[Install]
WantedBy=multi-user.target
EOF

        sudo systemctl daemon-reload
        sudo systemctl enable ${SERVICE_NAME}.service
        sudo systemctl start ${SERVICE_NAME}.service
        
        echo "✅ Daemon '${SERVICE_NAME}' setup and started."
        echo "ℹ️ Use 'sudo systemctl status ${SERVICE_NAME}' to check status."
        ;;
    *)
        usage
        exit 1
        ;;
esac
