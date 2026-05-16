# Scope

- This repo is only the Dockerized `korobas` environment. The executable sources of truth are `Dockerfile`, `docker-compose.yaml`, `entrypoint.sh`, `sshd_config`, and `Taskfile.yml`.
- There is no app source tree, CI workflow, formatter config, or repo-local test suite. Do not invent `npm test`, `pytest`, or similar checks here.

# Verified Commands

- Validate Compose config with `docker compose config`.
- Validate the entrypoint script with `sh -n entrypoint.sh`.
- Build the desktop image with `task build:desktop`.
- Build the core image with `task build:core`.
- Do not run `docker compose up` or `task up` unless the user explicitly asks to start or rebuild the container end-to-end.

# Wiring That Matters

- Compose runs a single service, `korobas`, and bind-mounts `./korobas` to `/home/korobas`.
- Changes under `korobas/` affect the mounted home directly. Changes to `Dockerfile`, `entrypoint.sh`, `sshd_config`, or Compose config require rebuilds.
- `entrypoint.sh` runs as `root`, starts SSH unconditionally, appends `KOROBAS_AUTHORIZED_KEYS` when provided, then drops to user `korobas` via `gosu`.
- The long-running process is still `CMD ["sleep", "infinity"]`; the entrypoint is bootstrap only.

# Desktop vs Core

- There is no separate `KOROBAS_IMAGE_VARIANT` switch anymore. Desktop vs core is inferred from `KOROBAS_IMAGE`.
- Any `KOROBAS_IMAGE` containing `desktop` enables XRDP in both `Dockerfile` and `entrypoint.sh`.
- The matching base images are:
  - desktop: `KOROBAS_IMAGE=ghcr.io/psauxwwf/korobas-desktop:latest` with `KOROBAS_BASE_IMAGE=scottyhardy/docker-remote-desktop:latest`
  - core: `KOROBAS_IMAGE=ghcr.io/psauxwwf/korobas-core:latest` with `KOROBAS_BASE_IMAGE=debian:13`
- Keep `KOROBAS_IMAGE` and `KOROBAS_BASE_IMAGE` aligned when editing build logic or task definitions.

# Image Details

- The image creates user/group `korobas` from build args `KOROBAS_UID` and `KOROBAS_GID`; Compose pins both to `1000`.
- The image installs `sudo` and grants `korobas` passwordless sudo via `/etc/sudoers.d/korobas`.
- `mise` is installed into `/usr/local/bin/mise`, but its runtime config comes from the bind-mounted home and dotfiles, not from the repo root.
- `sshd_config` enables both password and public-key auth. If auth behavior changes, keep `sshd_config` and `entrypoint.sh` in sync.

# Dotfiles And Releases

- The repo does not own the real dotfiles source. `entrypoint.sh` clones `https://github.com/psauxwwf/.dotfiles.git` branch `no-gui` into `/home/korobas/.dotfiles` at runtime and then runs `stow`.
- `mise install` and `mise run install` are part of the runtime bootstrap. Do not run `mise` commands unless the user explicitly asks.
- `task release` only archives `docker-compose.yaml` and `korobas/`; it does not package `Dockerfile`, `entrypoint.sh`, or `sshd_config`. Image-level changes need rebuilt/pushed images, not just a new tarball.

# Network And Naming

- Preserve the fixed bridge network name `korobas`, subnet `172.19.100.0/24`, gateway `172.19.100.1`, and container IP `172.19.100.2` unless the user explicitly wants networking changed.
- Current image tags are `ghcr.io/psauxwwf/korobas-desktop:latest` and `ghcr.io/psauxwwf/korobas-core:latest`.
