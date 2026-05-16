# Korobas

`korobas` is a Dockerized environment with a ready-to-use home directory, SSH access, and an RDP session.

The project is intended to quickly bring up a consistent working environment without manual system setup: the container creates the `korobas` user, applies dotfiles, starts `sshd` and XRDP, and then installs tools via `mise`.

## What Is Included

- Docker image based on `scottyhardy/docker-remote-desktop`
- `korobas` user with passwordless `sudo`
- SSH access into the container
- RDP access to the remote desktop session
- bootstrap logic via `entypoint.sh`
- dotfiles from `https://github.com/psauxwwf/.dotfiles`
- tools and extra setup via `mise`

## Run

Download the ready-made archive from the latest GitHub Release, extract it, and start the container:

```bash
wget -O korobas.tar.gz https://github.com/psauxwwf/korobas/releases/latest/download/korobas.tar.gz
tar -xzf korobas.tar.gz
docker compose up -d
```

## .env Examples

`.env` for desktop mode:

```dotenv
KOROBAS_IMAGE=ghcr.io/psauxwwf/korobas-desktop:latest
KOROBAS_AUTHORIZED_KEYS=
KOROBAS_PASSWORD=korobas
```

`.env` for core mode:

```dotenv
KOROBAS_IMAGE=ghcr.io/psauxwwf/korobas-core:latest
KOROBAS_AUTHORIZED_KEYS=
KOROBAS_PASSWORD=korobas
```

## Build And Up

Build the image locally and recreate the container:

```bash
task up
```

## Publish Release

Build `korobas.tar.gz` and publish it to a GitHub Release:

```bash
task release
```

## Connect

Connect over SSH:

```bash
ssh korobas@172.19.100.2
```

Connect over RDP:

```bash
remmina -c rdp://korobas@172.19.100.2
```

## Mise

After the first container start, it automatically runs `mise install` and `mise run install`.

## Installed Tools

The environment installs the following tooling via `mise`.

- JavaScript and Node.js: `node`, `bun`, `ansible-language-server`, `bash-language-server`, `dockerfile-language-server-nodejs`, `eslint`, `@microsoft/compose-language-service`, `prettier`, `pyright`, `some-sass-language-server`, `vscode-langservers-extracted`, `yaml-language-server`
- Python: `python`, `uv`, `black`, `clangd`, `clang-format`, `ruff`, `ruff-lsp`, `sqlit-tui`
- Go: `go`, `golangci-lint`, `golangci-lint-langserver`, `protols`, `delve`, `templ`
- AI and agent tools: `skills`, `opensrc`, `@oh-my-pi/pi-coding-agent`, `lightpanda browser`, `agent-browser`, `OfficeCLI`
- Markup and LSP utilities: `hadolint`, `marksman`, `pandoc`, `shellcheck`, `shfmt`, `superhtml`, `taplo`, `terraform-ls`, `tinymist`, `typst`, `typstyle`, `ghorg`, `buildifier`, `buf`
- General CLI tools: `chisel`, `cloudflared`, `dust`, `helix`, `jq`, `lazydocker`, `lazygit`, `lsd`, `rclone`, `starship`, `task`, `terraform`, `yazi`, `yt-dlp`, `zellij`, `zoxide`, `btop`, `github-cli`, `gitleaks`, `trufflehog`, `ripgrep`, `fd`, `worktrunk`, `llmfit`, `gowall`, `t2s`, `krot`, `zema`

The post-install `mise run install` task also installs the following extra tools:

- Python packages from `~/.config/mise/requirements.txt`
- Go tools: `gopls`, `goimports`
- Global npm packages: `typescript`, `typescript-language-server`, `@vue/language-server`, `@vue/typescript-plugin`

Useful commands inside the environment:

```bash
mise install
mise run install
mise run prune
```
