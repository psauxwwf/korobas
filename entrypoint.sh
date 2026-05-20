#!/bin/bash
set -eu

home_dir=/home/korobas
dotfiles_dir="$home_dir/.dotfiles"
bootstrap_marker="$home_dir/.local/state/korobas/mise-bootstrap-done"
bind_address="${KOROBAS_BIND_ADDRESS:-172.19.100.2}"
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

start_xrdp() {
	local image_name xrdp_sesman_bin xrdp_bin

	image_name="${KOROBAS_IMAGE:-ghcr.io/psauxwwf/korobas-desktop:latest}"
	case "$image_name" in
	*desktop*) ;;
	*) return ;;
	esac

	xrdp_sesman_bin=$(command_path xrdp-sesman "xrdp binaries are missing in the image")
	xrdp_bin=$(command_path xrdp "xrdp binaries are missing in the image")

	mkdir -p /var/run/xrdp
	rm -f /var/run/xrdp/xrdp-sesman.pid /var/run/xrdp/xrdp.pid
	"$xrdp_sesman_bin"
	"$xrdp_bin"
}

add_authorized_keys() {
	local authorized_keys_file

	if [ -z "${KOROBAS_AUTHORIZED_KEYS:-}" ]; then
		return
	fi

	install -d -m 0700 "$home_dir/.ssh"
	authorized_keys_file="$home_dir/.ssh/authorized_keys"
	touch "$authorized_keys_file"
	chmod 0600 "$authorized_keys_file"

	printf '%b\n' "${KOROBAS_AUTHORIZED_KEYS}" | while IFS= read -r pubkey || [ -n "$pubkey" ]; do
		[ -n "$pubkey" ] || continue
		grep -Fqx -- "$pubkey" "$authorized_keys_file" || printf '%s\n' "$pubkey" >>"$authorized_keys_file"
	done
}

start_ssh() {
	local sshd_bin ssh_keygen_bin

	sshd_bin=$(command_path sshd "OpenSSH binaries are missing in the image")
	ssh_keygen_bin=$(command_path ssh-keygen "OpenSSH binaries are missing in the image")

	mkdir -p "$home_dir" /etc/ssh /run/sshd
	"$ssh_keygen_bin" -A >/dev/null 2>&1
	printf 'korobas:%s\n' "${KOROBAS_PASSWORD:-korobas}" | chpasswd
	add_authorized_keys
	"$sshd_bin"
}

prepare_home() {
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
	rm -rf "$dotfiles_dir"
	git clone --branch no-gui --single-branch --depth 1 https://github.com/psauxwwf/.dotfiles.git "$dotfiles_dir"
}

sync_dotfiles() {
	local before_revision after_revision

	if [ ! -d "$dotfiles_dir/.git" ]; then
		clone_dotfiles
		dotfiles_changed=true
	else
		before_revision=$(git -C "$dotfiles_dir" rev-parse HEAD 2>/dev/null || true)
		if dotfiles_has_local_changes; then
			printf '%s\n' "Stashing local dotfiles changes in $dotfiles_dir before update" >&2
			stash_dotfiles_changes
			dotfiles_changed=true
		fi

		git -C "$dotfiles_dir" pull --ff-only
		after_revision=$(git -C "$dotfiles_dir" rev-parse HEAD 2>/dev/null || true)
		[ "$before_revision" = "$after_revision" ] || dotfiles_changed=true
	fi

	stow -d "$dotfiles_dir" -t "$home_dir" --no-folding --verbose=1 .
}

bootstrap_mise() {
	if [ -f "$bootstrap_marker" ] && [ "$dotfiles_changed" != "true" ]; then
		return
	fi

	mise install --jobs=1
	mise run install --jobs=1
	touch "$bootstrap_marker"
}

ensure_main_zellij_session() {
	log "Ensuring Zellij session 'main'"

	if ! zsh -lc 'command -v zellij >/dev/null 2>&1'; then
		log "Zellij is not available in the user shell; skipping session startup"
		return
	fi

	if zsh -lc 'exec zellij attach --create-background main >/dev/null'; then
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

	socat TCP-LISTEN:8082,bind="$bind_address",fork,reuseaddr TCP:127.0.0.1:8082 >/dev/null 2>&1 &
	log "Started Zellij proxy on $bind_address:8082 -> 127.0.0.1:8082 (pid $!)"
}

start_opencode() {
	local cors

	cors="${OPENCODE_CORS:-}"

	if ! zsh -lc 'command -v opencode >/dev/null 2>&1'; then
		die "opencode is not available in the user shell" 127
	fi

	if pgrep -f "opencode web --hostname=$bind_address --port=8000" >/dev/null 2>&1; then
		log "Opencode already running on $bind_address:8000"
		return
	fi

	OPENCODE_CORS="$cors" zsh -lc '
			if [[ -n "$OPENCODE_CORS" ]]; then
				exec opencode web "--hostname=$KOROBAS_BIND_ADDRESS" "--port=8000" "--cors=$OPENCODE_CORS"
			fi
			exec opencode web "--hostname=$KOROBAS_BIND_ADDRESS" "--port=8000"
		' &
	log "Started opencode on $bind_address:8000 (pid $!)"
}

run_as_korobas() {
	chown -R korobas:korobas "$home_dir"
	exec gosu korobas "$0" "$@"
}

run_root_phase() {
	start_xrdp
	start_ssh
	run_as_korobas "$@"
}

run_user_phase() {
	prepare_home
	sync_dotfiles
	bootstrap_mise
	ensure_main_zellij_session
	start_zellij_proxy
	start_opencode

	if [ -z "${1:-}" ]; then
		exec sleep infinity
	fi

	exec "$@"
}

if [ "$(id -u)" -eq 0 ]; then
	run_root_phase "$@"
fi

run_user_phase "$@"
