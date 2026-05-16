#!/bin/bash
set -eu

home_dir=/home/korobas
dotfiles_dir="$home_dir/.dotfiles"
bootstrap_marker="$home_dir/.local/state/korobas/mise-bootstrap-done"
dotfiles_changed=false

die() {
	echo "$1" >&2
	exit "${2:-1}"
}

command_path() {
	command -v "$1" 2>/dev/null || die "$2" 127
}

start_xrdp() {
	local image_name xrdp_sesman_bin xrdp_bin

	image_name="${KOROBAS_IMAGE:-ghcr.io/psauxwwf/korobas-desktop:latest}"
	case "$image_name" in
		*desktop*) ;;
		*) return 0 ;;
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

	[ -n "${KOROBAS_AUTHORIZED_KEYS:-}" ] || return 0

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

current_dotfiles_revision() {
	git -C "$dotfiles_dir" rev-parse HEAD 2>/dev/null || true
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
		before_revision=$(current_dotfiles_revision)
		git -C "$dotfiles_dir" pull --ff-only
		after_revision=$(current_dotfiles_revision)
		[ "$before_revision" = "$after_revision" ] || dotfiles_changed=true
	fi

	stow -d "$dotfiles_dir" -t "$home_dir" .
}

bootstrap_mise() {
	if [ -f "$bootstrap_marker" ] && [ "$dotfiles_changed" != "true" ]; then
		return 0
	fi

	mise install --jobs=1
	mise run install --jobs=1
	touch "$bootstrap_marker"
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

	if [ -z "${1:-}" ]; then
		exec sleep infinity
	fi

	exec "$@"
}

if [ "$(id -u)" -eq 0 ]; then
	run_root_phase "$@"
fi

run_user_phase "$@"
