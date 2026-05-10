#!/usr/bin/env bash
# Orchestra Management Script
# Simplifies deployment, teardown, and automation (Dockcheck & Git Sync)

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
UPDATER_SERVICE="orchestra-updater"
GIT_SYNC_SERVICE="orchestra-git-sync"

usage() {
    echo "Usage: $0 {up|down|status|logs|logs-update|install-dockcheck|setup-daemon|self-update|setup-git-sync}"
    echo ""
    echo "Orchestra Commands:"
    echo "  up                : Pull latest images and start the orchestra"
    echo "  down              : Stop and remove the orchestra containers"
    echo "  status            : Show status of the orchestra"
    echo "  logs              : Show logs for all services (via Docker)"
    echo ""
    echo "Dockcheck (Image Updates):"
    echo "  install-dockcheck : Download dockcheck.sh and dependencies (regctl)"
    echo "  setup-daemon      : Create systemd timer for auto-image-updates"
    echo "  logs-update       : View logs for the image updater daemon"
    echo ""
    echo "Git Sync (Code Updates):"
    echo "  self-update       : Check for changes in 'main' and redeploy if found"
    echo "  setup-git-sync    : Create systemd timer for auto-code-updates"
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
        echo "📜 Showing logs for $UPDATER_SERVICE..."
        journalctl -u "$UPDATER_SERVICE" -f
        ;;
    install-dockcheck)
        if [ ! -f "$DOCKCHECK_PATH" ]; then
            echo "📥 Downloading Dockcheck..."
            curl -fsSL "$DOCKCHECK_URL" -o "$DOCKCHECK_PATH"
            chmod +x "$DOCKCHECK_PATH"
        fi
        if ! command -v regctl &> /dev/null; then
            echo "📥 Downloading regctl..."
            sudo curl -L "$REGCTL_URL" -o /usr/local/bin/regctl
            sudo chmod +x /usr/local/bin/regctl
        fi
        echo "✅ Dockcheck and dependencies installed."
        ;;
    setup-daemon)
        echo "⚙️ Setting up systemd timer for image updates..."
        cat <<EOF | sudo tee /etc/systemd/system/${UPDATER_SERVICE}.service
[Unit]
Description=Ramper Orchestra Auto-Updater
After=network.target docker.service

[Service]
Type=oneshot
User=root
WorkingDirectory=$SCRIPT_DIR
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=$DOCKCHECK_PATH -u -n -r
EOF
        cat <<EOF | sudo tee /etc/systemd/system/${UPDATER_SERVICE}.timer
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
        sudo systemctl enable --now ${UPDATER_SERVICE}.timer
        echo "✅ Timer '${UPDATER_SERVICE}' active."
        ;;
    self-update)
        echo "🔄 Checking for code updates in repository..."
        git fetch origin main
        
        UPSTREAM=${1:-'@{u}'}
        LOCAL=$(git rev-parse @)
        REMOTE=$(git rev-parse "$UPSTREAM")
        BASE=$(git merge-base @ "$UPSTREAM")

        if [ "$LOCAL" = "$REMOTE" ]; then
            echo "✅ Code is up to date."
        elif [ "$LOCAL" = "$BASE" ]; then
            echo "📥 New changes detected. Pulling..."
            git pull origin main
            echo "🚀 Redeploying orchestra..."
            "$0" up
        else
            echo "⚠️ Diverged branches. Manual intervention required."
        fi
        ;;
    setup-git-sync)
        echo "⚙️ Setting up systemd timer for code git sync..."
        cat <<EOF | sudo tee /etc/systemd/system/${GIT_SYNC_SERVICE}.service
[Unit]
Description=Ramper Orchestra Git Sync
After=network.target

[Service]
Type=oneshot
User=root
WorkingDirectory=$SCRIPT_DIR
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=/usr/bin/bash $SCRIPT_DIR/orchestra.sh self-update
EOF
        cat <<EOF | sudo tee /etc/systemd/system/${GIT_SYNC_SERVICE}.timer
[Unit]
Description=Ramper Orchestra Git Sync Timer

[Timer]
OnBootSec=2min
OnUnitActiveSec=15min
Persistent=true

[Install]
WantedBy=timers.target
EOF
        sudo systemctl daemon-reload
        sudo systemctl enable --now ${GIT_SYNC_SERVICE}.timer
        echo "✅ Timer '${GIT_SYNC_SERVICE}' active (every 15 min)."
        ;;
    *)
        usage
        exit 1
        ;;
esac
