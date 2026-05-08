# Ramper Web Orchestra

A micro-orchestra designed to deploy the Ramper website on a Proxmox Docker LXC. It features internal traffic management via Caddy, monitoring via Uptime Kuma, and automated updates via Dockcheck.

## Architecture

- **Web Application**: Astro-based site (`ghcr.io/alpargatagazer/ramper-web`).
- **Proxy**: Caddy acting as a multi-port internal reverse proxy.
- **Monitoring**: Uptime Kuma to track service health.
- **Auto-Updates**: Integrated `dockcheck.sh` automation for GHCR and other registries.

## Prerequisites

### 1. GHCR Authentication (GitHub Container Registry)

To pull the private/public web image, the host (LXC) must be authenticated. You will need a **Personal Access Token (PAT)** with `read:packages` permissions.

Run this command on your LXC:

```bash
echo "YOUR_PAT_TOKEN" | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin
```

### 2. Network Configuration

The orchestra exposes two distinct ports to the host:
- **Port 8123**: Ramper Web.
- **Port 8124**: Uptime Kuma.

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
- `./orchestra.sh logs`: View live logs.

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

## Persistence

Persistent data is stored in the `./volumes` directory:
- `caddy_data/`: Caddy certificates and config.
- `uptime-kuma/`: Database and settings for the monitoring service.
