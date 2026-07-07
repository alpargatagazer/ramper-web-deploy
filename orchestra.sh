#!/usr/bin/env bash
# Orchestra Management Script
# Simplifies deployment, teardown, and automation (Watchtower & Git Sync)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Load environment variables
if [ -f .env ]; then
    set -a
    source .env
    set +a
fi

# Load image versions
if [ -f .env.images ]; then
    set -a
    source .env.images
    set +a
fi

GIT_SYNC_SERVICE="orchestra-git-sync"

usage() {
    echo "Usage: $0 {up|down|status|logs|self-update|setup-git-sync|prune}"
    echo ""
    echo "Orchestra Commands:"
    echo "  up                : Pull latest images, start the orchestra, and cleanup"
    echo "  down              : Stop and remove the orchestra containers"
    echo "  status            : Show status of the orchestra"
    echo "  logs              : Show logs for all services (via Docker)"
    echo "  prune             : Remove dangling images and layers to save space"
    echo ""
    echo "Git Sync (Config/Infra Updates):"
    echo "  self-update       : Check for changes in 'main' and redeploy if found"
    echo "  setup-git-sync    : Create systemd timer for auto-config-updates (every 5min)"
    echo ""
    echo "Note: ramper-web image updates are handled automatically by Watchtower."
    echo "      Infrastructure image updates come via Renovate PRs merged to main."
}

case "$1" in
    up)
        echo "🔑 Ensuring Docker Compose secrets exist..."
        mkdir -p "$SCRIPT_DIR/secrets"
        if [ ! -f "$SCRIPT_DIR/secrets/listmonk_db_password.txt" ]; then
            echo "🔑 Generating secure database password..."
            if command -v openssl &> /dev/null; then
                openssl rand -hex 16 > "$SCRIPT_DIR/secrets/listmonk_db_password.txt"
            else
                echo "db_pass_$(date +%s)_$RANDOM" > "$SCRIPT_DIR/secrets/listmonk_db_password.txt"
            fi
        fi
        if [ ! -f "$SCRIPT_DIR/secrets/listmonk_admin_username.txt" ]; then
            echo "admin" > "$SCRIPT_DIR/secrets/listmonk_admin_username.txt"
        fi
        if [ ! -f "$SCRIPT_DIR/secrets/listmonk_admin_password.txt" ]; then
            echo "🔑 Generating secure Listmonk admin password..."
            if command -v openssl &> /dev/null; then
                openssl rand -hex 12 > "$SCRIPT_DIR/secrets/listmonk_admin_password.txt"
            else
                echo "admin_pass_$(date +%s)_$RANDOM" > "$SCRIPT_DIR/secrets/listmonk_admin_password.txt"
            fi
            echo "⚠️ Note: Generated admin password saved in secrets/listmonk_admin_password.txt"
        fi

        # Dedicated API User credentials for the web container
        if [ ! -f "$SCRIPT_DIR/secrets/listmonk_api_username.txt" ]; then
            echo "apiuser" > "$SCRIPT_DIR/secrets/listmonk_api_username.txt"
        fi
        if [ ! -f "$SCRIPT_DIR/secrets/listmonk_api_password.txt" ]; then
            echo "🔑 Generating secure Listmonk API password..."
            if command -v openssl &> /dev/null; then
                openssl rand -hex 12 > "$SCRIPT_DIR/secrets/listmonk_api_password.txt"
            else
                echo "api_pass_$(date +%s)_$RANDOM" > "$SCRIPT_DIR/secrets/listmonk_api_password.txt"
            fi
            echo "⚠️ IMPORTANT: You MUST manually create an 'apiuser' in the Listmonk dashboard with the password found in secrets/listmonk_api_password.txt before newsletters will work!"
        fi

        echo "🚀 Starting Postgres database..."
        docker compose up -d listmonk-db

        # Wait briefly for Postgres database to start accepting connections before running Listmonk migrations
        echo "⏳ Waiting for database to initialize..."
        sleep 5

        echo "🚀 Running Listmonk database install/upgrade..."
        docker compose run --rm listmonk ./listmonk --install --yes --idempotent || true
        docker compose run --rm listmonk ./listmonk --upgrade --yes || true

        echo "🚀 Starting Ramper Orchestra..."
        docker compose pull
        docker compose up -d --remove-orphans
        echo "🧹 Cleaning up old images..."
        docker image prune -f
        echo "✅ Orchestra is up and disk is clean."
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
    self-update)
        echo "🔄 Checking for code updates in repository..."
        git fetch origin main

        UPSTREAM="origin/main"
        LOCAL=$(git rev-parse HEAD)
        REMOTE=$(git rev-parse "$UPSTREAM")
        BASE=$(git merge-base HEAD "$UPSTREAM")

        if [ "$LOCAL" = "$REMOTE" ]; then
            echo "✅ Code is up to date."
        elif [ "$LOCAL" = "$BASE" ]; then
            echo "📥 New changes detected in $UPSTREAM. Pulling..."
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
OnUnitActiveSec=5min
Persistent=true

[Install]
WantedBy=timers.target
EOF
        sudo systemctl daemon-reload
        sudo systemctl enable --now ${GIT_SYNC_SERVICE}.timer
        echo "✅ Timer '${GIT_SYNC_SERVICE}' active (every 5 min)."
        ;;
    prune)
        echo "🧹 Removing dangling images and layers..."
        docker image prune -f
        ;;
    *)
        usage
        exit 1
        ;;
esac
