# Ramper Web Orchestra

A micro-orchestra designed to deploy the Ramper website on a Proxmox Docker LXC. It features internal traffic management via Caddy, monitoring via Uptime Kuma, and automated updates via Watchtower (for the web app) + Renovate (for infrastructure images).

## Architecture

- **Web Application**: Astro-based site (`ghcr.io/alpargatagazer/ramper-web`) with hybrid API routing for subscriptions and automated newsletter delivery.
- **Proxy**: Caddy acting as a multi-port internal reverse proxy.
- **Monitoring**: Uptime Kuma to track service health.
- **Logs**: Dozzle for a web-based view of container logs.
- **Newsletter**: Listmonk self-hosted email subscription manager.
- **Database**: PostgreSQL dedicated backend database for Listmonk.
- **Auto-Updates (Web App)**: Watchtower monitors only the `ramper-web` container and restarts it when a new image is published to GHCR.
- **Auto-Updates (Infrastructure)**: Renovate opens weekly PRs bumping pinned versions in `.env.images`. Merge the PR → git-sync timer picks it up and redeploys.

## Update Workflows

### ramper-web (your Astro site)

```
Push to main → GitHub Actions CI → Build + Test → Push :latest to GHCR
                                                        ↓
                                              Watchtower detects new digest (every 5min)
                                                        ↓
                                              Restarts ramper-web container
                                                        ↓
                                              Container starts → newsletter:send runs
                                              (sends email only if new post found)
```

### Infrastructure services (Caddy, Postgres, Listmonk, etc.)

```
Renovate PR (weekly) → You review + merge
                                ↓
                        git-sync timer (every 5min) detects new commit
                                ↓
                        git pull → docker compose up (with new image tags)
```

## Prerequisites

### 1. GHCR Authentication (GitHub Container Registry)

To pull the private/public web image, the host (LXC) must be authenticated. You will need a **Personal Access Token (PAT)** with `read:packages` permissions.

Run this command on your LXC:

```bash
echo "YOUR_PAT_TOKEN" | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin
```

> [!NOTE]
> Watchtower reads Docker's auth config (`/root/.docker/config.json`) to pull authenticated images from GHCR.

### 2. Network Configuration

The orchestra exposes distinct ports to the host:
- **Port 8123**: Ramper Web.
- **Port 8124**: Uptime Kuma.
- **Port 8125**: Dozzle (Logs).
- **Port 9000**: Listmonk (newsletter admin).

Configure your **Cloudflare Tunnel** (in its own LXC) to point to these specific ports based on your desired subdomains/paths.

## Initial Setup

1. Clone this repository into your LXC.
2. Copy `.env.example` to `.env` and fill in values.
3. `.env.images` is already committed and managed by Renovate — no need to copy it.
4. Deploy the stack:

```bash
./orchestra.sh up
```

## Management

Use the `orchestra.sh` script for common operations:

- `./orchestra.sh up`: Pull latest images, start the entire stack, and cleanup.
- `./orchestra.sh down`: Stop and remove containers.
- `./orchestra.sh status`: View container health.
- `./orchestra.sh logs`: View live logs of the services.
- `./orchestra.sh prune`: Remove dangling images to free disk space.

## Automated Updates

### Web App (Watchtower)

Watchtower runs as a service in the compose stack and polls GHCR every 5 minutes. It only updates containers that carry the `com.centurylinklabs.watchtower.enable=true` label — currently only `ramper-web`.

You can optionally configure Watchtower notifications by setting `WATCHTOWER_NOTIFICATION_URL` in `.env` (supports Slack, Discord, Telegram, email via shoutrrr).

### Infrastructure Images (Renovate + Git Sync)

Image versions are pinned in `.env.images` with Renovate annotations. Renovate opens PRs automatically when upstream images have new versions. Once merged, the git-sync timer picks up the change within 5 minutes and redeploys.

To enable the git-sync timer on the LXC:

```bash
./orchestra.sh setup-git-sync
```

## Secrets Management

This deployment implements **Docker Compose Secrets** to avoid storing passwords in environment variables:
- Admin credentials and database passwords are stored inside the `./secrets/` directory on the host.
- These files are automatically generated with secure random strings upon running `./orchestra.sh up` for the first time.
  - `./secrets/listmonk_db_password.txt`: Database access password.
  - `./secrets/listmonk_admin_username.txt`: Listmonk Superadmin user.
  - `./secrets/listmonk_admin_password.txt`: Listmonk Superadmin password.
  - `./secrets/listmonk_api_username.txt`: API user for the web container (defaults to `apiuser`).
  - `./secrets/listmonk_api_password.txt`: Auto-generated password for the API user.

> [!IMPORTANT]
> Because Listmonk only auto-creates the Superadmin user on installation, the auto-generated API user will not exist in the database.
> After the first deployment, you **must** log into the Listmonk dashboard using the admin credentials, navigate to Settings → Users, and manually create the `apiuser` using the password found in `./secrets/listmonk_api_password.txt`. The web container relies on this API user to send automated newsletters.

## Persistence

Persistent data is stored in the `./volumes` directory:
- `caddy_data/`: Caddy certificates and config.
- `uptime-kuma/`: Database and settings for the monitoring service.
- `listmonk_db/`: PostgreSQL database files.
- `web_data/`: State file (`last-newsletter.json`) for newsletter tracking.
