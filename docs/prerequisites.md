# Prerequisites

Everything runs in Docker, so you only need Docker and a few command-line tools. `scripts/setup.sh --check` tells you what is missing.

## Windows: WSL2 + Docker Desktop (recommended)

1. **Install WSL2 with Ubuntu.** In PowerShell as administrator, run `wsl --install -d Ubuntu`, then reboot and create your Linux user.
2. **Install [Docker Desktop](https://www.docker.com/products/docker-desktop/)** and set it up:
   - *Settings → General*: enable **Use the WSL 2 based engine**.
   - *Settings → Resources → WSL integration*: enable the integration for your **Ubuntu** distro.
   - Check it from an Ubuntu terminal: `docker info` and `docker compose version` should both work, without `sudo`.
3. **Install the tools** in Ubuntu:
   ```bash
   sudo apt update && sudo apt install -y git curl coreutils rsync
   ```
   (`rsync` is optional; `scripts/test-plugin.sh` uses it when available.)
4. **Clone inside WSL**, not on the Windows drive:
   ```bash
   mkdir -p ~/GIT && cd ~/GIT
   git clone https://github.com/RobEngelen/kong-pongo-busted-framework.git
   ```
   - The Linux filesystem is much faster than `/mnt/c`.
   - Kong's integration tests **fail** on `/mnt/c`, because unix sockets can't be created there ([kong-pongo#368](https://github.com/Kong/kong-pongo/issues/368)).
   - You can still open the files from Windows at `\\wsl.localhost\Ubuntu\home\<you>\GIT\...`, or with VS Code's *WSL* extension (`code .` from the Ubuntu terminal).
5. **Line endings.** Make sure Git inside WSL doesn't convert to CRLF:
   ```bash
   git config --global core.autocrlf input
   ```
   This repo forces LF through `.gitattributes`, but your plugin repos might not. Shell scripts with CRLF fail with `$'\r': command not found`.

## Linux

- Install Docker Engine and the compose plugin (`docker compose`), plus `git`, `curl` and `coreutils`.
- Add yourself to the `docker` group so `docker` works without `sudo`:
  ```bash
  sudo usermod -aG docker $USER
  ```
  Log out and back in afterwards.

## macOS

- Install Docker Desktop (or another Docker runtime with `docker compose`) and `git`.
- Install coreutils with `brew install coreutils`; older macOS versions lack `realpath`.

## Then

```bash
scripts/setup.sh
```

This installs Pongo (pinned version) into `~/.local/share/kong-pongo` and links it as `~/.local/bin/pongo`. Re-running it is safe; it also updates Pongo when the pinned version in the script changes.

| To change | Set |
|---|---|
| Pongo version | `PONGO_VERSION=<tag>` |
| Install location | `PONGO_HOME=<dir>` |
| Link location | `PONGO_BIN_DIR=<dir>` |

## Behind a corporate proxy

- Pongo passes the standard `http_proxy` / `https_proxy` / `no_proxy` variables to Docker builds and containers.
- If the proxy inspects TLS with its own CA, build the test image with that CA:
  ```bash
  pongo build --custom-ca-cert /path/to/ca.crt
  ```
  You can also set `PONGO_CUSTOM_CA_CERT`.
- Docker Hub rate limits: run `docker login`, or set `DOCKER_USERNAME` / `DOCKER_PASSWORD`.
