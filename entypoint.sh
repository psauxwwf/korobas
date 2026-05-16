#!/bin/bash
set -eu

home_dir=/home/korobas
bootstrap_marker="$home_dir/.local/state/korobas/mise-bootstrap-done"
ssh_enabled="${KOROBAS_SSH_ENABLED:-true}"
xrdp_enabled="${KOROBAS_XRDP_ENABLED:-true}"
dotfiles_repo=https://github.com/psauxwwf/.dotfiles.git
dotfiles_branch=no-gui

die() {
	echo "$1" >&2
	exit "${2:-1}"
}

require_command() {
	command -v "$1" >/dev/null 2>&1 || die "$2" 127
}

command_path() {
	command -v "$1" 2>/dev/null || die "$2" 127
}

start_xrdp() {
	local xrdp_sesman_bin xrdp_bin

	[ "$xrdp_enabled" = "true" ] || return 0

	xrdp_sesman_bin=$(command_path xrdp-sesman "xrdp binaries are missing in the image")
	xrdp_bin=$(command_path xrdp "xrdp binaries are missing in the image")

	mkdir -p /var/run/xrdp
	rm -f /var/run/xrdp/xrdp-sesman.pid /var/run/xrdp/xrdp.pid
	"$xrdp_sesman_bin"
	"$xrdp_bin"
}

add_authorized_keys() {
	[ -n "${KOROBAS_AUTHORIZED_KEYS:-}" ] || return 0

	install -d -m 0700 "$home_dir/.ssh"
	authorized_keys_file="$home_dir/.ssh/authorized_keys"
	touch "$authorized_keys_file"
	chmod 0600 "$authorized_keys_file"

	printf '%b\n' "${KOROBAS_AUTHORIZED_KEYS}" | while IFS= read -r pubkey || [ -n "$pubkey" ]; do
		[ -n "$pubkey" ] || continue
		grep -Fqx -- "$pubkey" "$authorized_keys_file" || printf '%s\n' "$pubkey" >> "$authorized_keys_file"
	done
}

start_ssh() {
	local sshd_bin ssh_keygen_bin

	[ "$ssh_enabled" = "true" ] || return 0

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

ensure_dotfiles() {
	if [ ! -d "$home_dir/.dotfiles" ]; then
		git clone --branch "$dotfiles_branch" --single-branch --depth 1 "$dotfiles_repo" "$home_dir/.dotfiles"
	fi

	stow -d "$home_dir/.dotfiles" -t "$home_dir" .
}

bootstrap_mise() {
	[ ! -f "$bootstrap_marker" ] || return 0

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
	ensure_dotfiles
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
