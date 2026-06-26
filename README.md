# Ramper Web Orchestra

A micro-orchestra designed to deploy the Ramper website on a Proxmox Docker LXC. It features internal traffic management via Caddy, monitoring via Uptime Kuma, and automated updates via Dockcheck.

## Architecture

- **Web Application**: Astro-based site (`ghcr.io/alpargatagazer/ramper-web`) with hybrid API routing for subscriptions.
- **Proxy**: Caddy acting as a multi-port internal reverse proxy.
- **Monitoring**: Uptime Kuma to track service health.
- **Logs**: Dozzle for a web-based view of container logs.
- **Newsletter**: Listmonk self-hosted email subscription manager.
- **Database**: PostgreSQL dedicated backend database for Listmonk.
- **Auto-Updates**: Integrated `dockcheck.sh` automation for GHCR and other registries.

## Prerequisites

### 1. GHCR Authentication (GitHub Container Registry)

To pull the private/public web image, the host (LXC) must be authenticated. You will need a **Personal Access Token (PAT)** with `read:packages` permissions.

Run this command on your LXC:

```bash
echo "YOUR_PAT_TOKEN" | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin
```

### 2. Network Configuration

The orchestra exposes three distinct ports to the host:
- **Port 8123**: Ramper Web.
- **Port 8124**: Uptime Kuma.
- **Port 8125**: Dozzle (Logs).

Configure your **Cloudflare Tunnel** (in its own LXC) to point to these specific ports based on your desired subdomains/paths.

## Initial Setup

1. Clone this repository into your LXC.
2. Review the `.env` file (created from `.env.example`).
3. Deploy the stack:

```bash
./orchestra.sh up
```

## Management

Use the `orchestra.sh` script for common operations:

- `./orchestra.sh up`: Start or update the entire stack.
- `./orchestra.sh down`: Stop and remove containers.
- `./orchestra.sh status`: View container health.
- `./orchestra.sh logs`: View live logs of the services.
- `./orchestra.sh logs-update`: View the logs of the background updater (Dockcheck).

## Automated Updates (Dockcheck)

Instead of manually checking for new versions, we use `dockcheck.sh` automated via a systemd daemon.

### 1. Install Dockcheck
Download the latest script directly:
```bash
./orchestra.sh install-dockcheck
```

### 2. Setup the Auto-Update Daemon
This will create a systemd service that runs Dockcheck every hour to check and apply updates:
```bash
./orchestra.sh setup-daemon
```

You can check the status of the updater with:
```bash
sudo systemctl status orchestra-updater
```

### 3. Setup Auto-Code Updates (Git Sync)
To keep your orchestration code (Caddyfile, Compose, etc.) always up to date with the `main` branch, you can enable the Git sync timer:
```bash
./orchestra.sh setup-git-sync
```
This will check for changes in the repository every 15 minutes and run `./orchestra.sh up` automatically if new code is pulled.

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
> After the first deployment, you **must** log into the Listmonk dashboard using the admin credentials, navigate to Settings -> Users, and manually create the `apiuser` using the password found in `./secrets/listmonk_api_password.txt`. The web container relies on this API user to send automated newsletters.

## Persistence

Persistent data is stored in the `./volumes` directory:
- `caddy_data/`: Caddy certificates and config.
- `uptime-kuma/`: Database and settings for the monitoring service.
- `listmonk_db/`: PostgreSQL database files.
- `web_data/`: State file (`last-newsletter.json`) for newsletter tracking.
