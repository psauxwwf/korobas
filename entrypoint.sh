#!/bin/bash
set -eu

home_dir="/home/korobas"
dotfiles_dir="$home_dir/.dotfiles"
bootstrap_marker="$home_dir/.local/state/korobas/mise-bootstrap-done"
mise_install_log="$home_dir/.local/state/korobas/mise-run-install.log"

dotfiles_changed=false

die() {
	echo "$1" >&2
	exit "${2:-1}"
}

log() {
	printf '[entrypoint] %s\n' "$1" >&2
}

command_path() {
	command -v "$1" 2>/dev/null || die "$2" 127
}

user_shell_has() {
	zsh -lc "command -v \"$1\" >/dev/null 2>&1"
}

start_xrdp() {
	local xrdp_sesman_bin xrdp_bin

	case "${KOROBAS_IMAGE:-ghcr.io/psauxwwf/korobas-desktop:latest}" in
	*desktop*)
		log "Starting XRDP"
		;;
	*)
		log "Skipping XRDP for non-desktop image ${KOROBAS_IMAGE:-ghcr.io/psauxwwf/korobas-desktop:latest}"
		return
		;;
	esac

	xrdp_sesman_bin=$(command_path xrdp-sesman "xrdp binaries are missing in the image")
	xrdp_bin=$(command_path xrdp "xrdp binaries are missing in the image")

	mkdir -p /var/run/xrdp
	rm -f /var/run/xrdp/xrdp-sesman.pid /var/run/xrdp/xrdp.pid
	"$xrdp_sesman_bin"
	"$xrdp_bin"
	log "XRDP started"
}

add_authorized_keys() {
	local authorized_keys_file

	if [ -z "${KOROBAS_AUTHORIZED_KEYS:-}" ]; then
		log "No additional authorized SSH keys configured"
		return
	fi

	log "Updating authorized SSH keys"
	install -d -m 0700 "$home_dir/.ssh"
	authorized_keys_file="$home_dir/.ssh/authorized_keys"
	touch "$authorized_keys_file"
	chmod 0600 "$authorized_keys_file"

	printf '%b\n' "${KOROBAS_AUTHORIZED_KEYS:-}" | while IFS= read -r pubkey || [ -n "$pubkey" ]; do
		[ -n "$pubkey" ] || continue
		grep -Fqx -- "$pubkey" "$authorized_keys_file" || printf '%s\n' "$pubkey" >>"$authorized_keys_file"
	done
}

start_ssh() {
	local sshd_bin ssh_keygen_bin

	log "Starting SSH server"
	sshd_bin=$(command_path sshd "OpenSSH binaries are missing in the image")
	ssh_keygen_bin=$(command_path ssh-keygen "OpenSSH binaries are missing in the image")

	mkdir -p "$home_dir" /etc/ssh /run/sshd
	"$ssh_keygen_bin" -A >/dev/null 2>&1
	printf 'korobas:%s\n' "${KOROBAS_PASSWORD:-korobas}" | chpasswd
	add_authorized_keys
	"$sshd_bin"
	log "SSH server started"
}

prepare_home() {
	log "Preparing home directories"
	export HOME="$home_dir"
	mkdir -p \
		"$home_dir/.cache/mise" \
		"$home_dir/.local/state/korobas" \
		"$home_dir/.local/state/mise" \
		"$home_dir/.local/share/mise"
}

dotfiles_has_local_changes() {
	[ -n "$(git -C "$dotfiles_dir" status --porcelain --untracked-files=normal 2>/dev/null)" ]
}

stash_dotfiles_changes() {
	git -C "$dotfiles_dir" stash push --include-untracked --message korobas-entrypoint-autostash >/dev/null
}

clone_dotfiles() {
	log "Cloning dotfiles into $dotfiles_dir"
	rm -rf "$dotfiles_dir"
	git clone --branch no-gui --single-branch --depth 1 https://github.com/psauxwwf/.dotfiles.git "$dotfiles_dir"
}

sync_dotfiles() {
	local before_revision after_revision

	log "Syncing dotfiles"
	if [ ! -d "$dotfiles_dir/.git" ]; then
		clone_dotfiles
		dotfiles_changed=true
	else
		before_revision=$(git -C "$dotfiles_dir" rev-parse HEAD 2>/dev/null || true)
		if dotfiles_has_local_changes; then
			log "Stashing local dotfiles changes in $dotfiles_dir before update"
			stash_dotfiles_changes
			dotfiles_changed=true
		fi

		log "Pulling latest dotfiles changes"
		git -C "$dotfiles_dir" pull --ff-only
		after_revision=$(git -C "$dotfiles_dir" rev-parse HEAD 2>/dev/null || true)
		[ "$before_revision" = "$after_revision" ] || dotfiles_changed=true
	fi

	log "Applying dotfiles with stow"
	stow -d "$dotfiles_dir" -t "$home_dir" --no-folding --verbose=1 .
}

bootstrap_mise() {
	if [ -f "$bootstrap_marker" ] && [ "$dotfiles_changed" != "true" ]; then
		log "Skipping mise bootstrap; marker is current"
		return
	fi

	log "Bootstrapping mise tools"
	mise install --jobs=1
	if ! mise run install --jobs=1 >"$mise_install_log" 2>&1; then
		die "mise run install failed; see $mise_install_log"
	fi
	touch "$bootstrap_marker"
	log "Mise bootstrap completed"
}

ensure_main_zellij_session() {
	log "Ensuring Zellij session 'main'"

	if ! user_shell_has zellij; then
		log "Zellij is not available in the user shell; skipping session startup"
		return
	fi

	if zsh -lc "zellij list-sessions --short 2>/dev/null | grep -Fqx -- 'main'"; then
		log "Zellij session 'main' already exists"
		return
	fi

	if zsh -lc "exec zellij attach --create-background 'main' >/dev/null"; then
		log "Started Zellij session 'main'"
		return
	fi

	log "Failed to start Zellij session 'main'"
}

start_zellij_proxy() {
	if ! command -v socat >/dev/null 2>&1; then
		log "socat is not available; skipping Zellij proxy"
		return
	fi

	socat TCP-LISTEN:8082,bind=0.0.0.0,fork,reuseaddr TCP:127.0.0.1:8082 >/dev/null 2>&1 &
	log "Started Zellij proxy on 0.0.0.0:8082 -> 127.0.0.1:8082 (pid $!)"
}

start_opencode() {
	if ! user_shell_has opencode; then
		die "opencode is not available in the user shell" 127
	fi

	log "Starting opencode on 0.0.0.0:8000"
	OPENCODE_CORS="${OPENCODE_CORS:-}" zsh -lc '
			if [[ -n "$OPENCODE_CORS" ]]; then
				exec opencode web "--hostname=0.0.0.0" "--port=8000" "--cors=$OPENCODE_CORS"
			fi
			exec opencode web "--hostname=0.0.0.0" "--port=8000"
		' &
	log "Started opencode on 0.0.0.0:8000 (pid $!)"
}

run_as_korobas() {
	log "Switching to user korobas"
	chown -R korobas:korobas "$home_dir"
	exec gosu korobas "$0" "$@"
}

run_root_phase() {
	log "Running root phase"
	start_xrdp
	start_ssh
	run_as_korobas "$@"
}

run_user_phase() {
	log "Running user phase"
	prepare_home
	sync_dotfiles
	bootstrap_mise
	ensure_main_zellij_session
	start_zellij_proxy
	start_opencode

	if [ -z "${1:-}" ]; then
		log "No command provided; sleeping forever"
		exec sleep infinity
	fi

	log "Executing command: $*"
	exec "$@"
}

if [ "$(id -u)" -eq 0 ]; then
	run_root_phase "$@"
fi

run_user_phase "$@"
