# Quick start

You need a Linux host on amd64 (the reference is a dedicated Ubuntu Server 26.04 VM) with Docker Engine 25 or
later and the Compose v2 plugin (2.24 or later), a user in the `docker` group, and a reverse proxy on another
host that serves HTTPS under a host name for USAS. Moving a USAS that already runs elsewhere? Follow
[installing.md](installing.md#moving-an-existing-usas-here) instead of steps 3 to 6: it must not start on an
empty data folder.

1. **Get the stack.**

   ```sh
   git clone https://github.com/HoneyBearTech/homelab-selene.git && cd homelab-selene
   ```

   Check out the latest release (`git checkout vX.Y.Z`) and verify it first
   ([verifying-releases.md](verifying-releases.md)), or stay on `main` the way the maintainer's server does
   ([upgrading.md](upgrading.md#following-main)).

2. **Configure it.**

   ```sh
   cp .env.example .env && chmod 600 .env
   ```

   Set `TZ`; `USAS_BIND_ADDRESS` to this host's address that the proxy reaches; `USAS_PUBLIC_URL` to the HTTPS
   address you will open (`https://usas.example.com`); and `USAS_TRUSTED_PROXIES` to the proxy's address. Change
   `CONFIG_ROOT` if you keep the data elsewhere (never inside `/var/lib/docker/volumes`:
   [installing.md](installing.md#where-data-lives)). Every setting is described in
   [interfaces.md](interfaces.md#settings). For restart notices from autoheal, also create `autoheal.env` from
   `autoheal.env.example` (mode `600`) with a webhook URL.

3. **Create USAS's data folder**, owned by the user USAS runs as (uid and gid 10001), readable by nobody else:

   ```sh
   . ./.env && sudo install -d -o 10001 -g 10001 -m 0700 "$CONFIG_ROOT/usas/config"
   ```

4. **Limit port 8080 to the proxy** with the `DOCKER-USER` rule in [installing.md](installing.md#the-firewall).
   Docker-published ports bypass `ufw`, so without it anyone who can reach the host can reach USAS's sign-in.

5. **Check and start.**

   ```sh
   docker compose config --quiet   # the file resolves with your settings
   docker compose up -d --wait     # waits until every service reports healthy
   docker compose ps
   ```

6. **Point the proxy at USAS and finish its setup.** In the reverse proxy, add a host for the name in
   `USAS_PUBLIC_URL` that forwards to `http://<USAS_BIND_ADDRESS>:8080`, with a TLS certificate and an access list
   that allows only your LAN and VPN. Open `USAS_PUBLIC_URL` and sign in with the setup code from the log
   (`docker compose logs usas`), choosing a password. On the **Account** page, add a passkey on each device you
   use, then turn on **Require a passkey**. Then connect USAS to your Proxmox cluster as its own documentation
   describes ([web UI](https://github.com/HoneyBearTech/ubuntu-server-auto-setup/blob/main/docs/web-ui.md)).

To upgrade later, follow [upgrading.md](upgrading.md); it starts with a backup.
