# Scope

- This repo is only a Dockerized `korobas` environment. The source-of-truth files are `Dockerfile.core`, `docker-compose.yaml`, `entypoint.sh`, and `sshd_config`.
- There is no app source tree, CI workflow, formatter config, or repo-local test suite. Do not invent `npm test`, `pytest`, or similar checks here.

# Verified Commands

- Validate image changes with `docker build -f Dockerfile.core .`.
- Validate Compose syntax with `docker compose config`.
- Validate the entrypoint script with `sh -n entypoint.sh`.
- Only run `docker compose up --build` when the user explicitly wants the container started or rebuilt end-to-end.

# Runtime Wiring

- Compose runs one service, `korobas`, from `Dockerfile.core` and bind-mounts `./korobas` to `/home/korobas`.
- Because `/home/korobas` is a bind mount, edits under `korobas/` affect the running container directly; changes to image-level files still require rebuilds.
- `entypoint.sh` starts as `root`, generates SSH host keys, applies `KOROBAS_PASSWORD`, optionally appends `KOROBAS_AUTHORIZED_KEYS` into `/home/korobas/.ssh/authorized_keys`, then drops to `korobas` via `gosu`.
- The long-running container process is still `CMD ["sleep", "infinity"]`; `entypoint.sh` is bootstrap, not the final workload.

# Image Details That Matter

- The image creates user/group `korobas` from build args `KOROBAS_UID` and `KOROBAS_GID`; Compose pins both to `1000`.
- The image installs `sudo` and grants `korobas` passwordless sudo via `/etc/sudoers.d/korobas`.
- `mise` is installed to `/usr/local/bin/mise`, and the image exports `PATH` with `/home/korobas/.local/share/mise/shims`.
- Locale is forced to UTF-8 in the image and `sshd_config` (`LANG=C.UTF-8`, `LC_ALL=C.UTF-8`) to avoid broken non-ASCII output over SSH.
- `sshd_config` enables both password and public-key auth. Keep auth changes consistent with both `sshd_config` and `entypoint.sh`.

# Dotfiles And Mise

- Active `mise` config is not in the repo root. It lives in `korobas/.dotfiles/.config/mise/`.
- The repo does contain `korobas/.dotfiles`; those files are what the bind-mounted home exposes in the container.
- `Dockerfile.core` clones template dotfiles into `/usr/local/share/korobas-home/.dotfiles`, but `entypoint.sh` only copies them when the mounted home does not already contain `.dotfiles`.
- `korobas/.dotfiles/.config/mise/config.toml` defines the repo-relevant `mise` tasks: `mise run install`, `mise run pip`, `mise run golang`, `mise run npm`, and `mise run prune`.
- `mise run install` no longer installs OS packages; it currently chains only `wget`, `pip`, `golang`, and `npm` tasks. Verify the actual task file before describing `mise` behavior.

# Known Stale Docs

- `README.md` still references copying caches into `./opencode/...`; the current bind-mounted home is `./korobas`, so do not repeat the old path.
- Older instructions that mention a root-level `config.toml`, `/home/opencode`, `OPENCODE_*`, or an `opencode` user are stale for this repo state.

# Network And Naming

- Preserve the current image name `ghcr.io/ghcr.io/korobas:latest` unless the user explicitly asks to change publishing coordinates.
- Compose uses a fixed bridge network named `korobas` with subnet `172.19.100.0/24` and container IP `172.19.100.2`; avoid accidental renames when editing networking.
