#!/bin/sh
set -eu

home_dir=/home/korobas
template_dir=/usr/local/share/korobas-home
bootstrap_marker="$home_dir/.local/state/korobas/mise-bootstrap-done"
ssh_enabled="${KOROBAS_SSH_ENABLED:-true}"
xrdp_enabled="${KOROBAS_XRDP_ENABLED:-true}"

if [ "$(id -u)" -eq 0 ]; then
	if [ "$xrdp_enabled" = "true" ]; then
		xrdp_sesman_bin=$(command -v xrdp-sesman || true)
		xrdp_bin=$(command -v xrdp || true)

		if [ -z "$xrdp_sesman_bin" ] || [ -z "$xrdp_bin" ]; then
			echo "xrdp binaries are missing in the image" >&2
			exit 127
		fi

		[ ! -f /var/run/xrdp/xrdp-sesman.pid ] || rm -f /var/run/xrdp/xrdp-sesman.pid
		[ ! -f /var/run/xrdp/xrdp.pid ] || rm -f /var/run/xrdp/xrdp.pid
		mkdir -p /var/run/xrdp
		"$xrdp_sesman_bin"
		"$xrdp_bin"
	fi

	if [ "$ssh_enabled" = "true" ]; then
		sshd_bin=$(command -v sshd || true)
		ssh_keygen_bin=$(command -v ssh-keygen || true)

		if [ -z "$sshd_bin" ] || [ -z "$ssh_keygen_bin" ]; then
			echo "OpenSSH binaries are missing in the image" >&2
			exit 127
		fi

		mkdir -p "$home_dir" /etc/ssh /run/sshd

		"$ssh_keygen_bin" -A >/dev/null 2>&1
		printf 'korobas:%s\n' "${KOROBAS_PASSWORD:-korobas}" | chpasswd
		if [ -n "${KOROBAS_AUTHORIZED_KEYS:-}" ]; then
			install -d -m 0700 "$home_dir/.ssh"
			authorized_keys_file="$home_dir/.ssh/authorized_keys"
			touch "$authorized_keys_file"
			chmod 0600 "$authorized_keys_file"
			printf '%b\n' "${KOROBAS_AUTHORIZED_KEYS}" | while IFS= read -r pubkey || [ -n "$pubkey" ]; do
				[ -n "$pubkey" ] || continue
				grep -Fqx -- "$pubkey" "$authorized_keys_file" || printf '%s\n' "$pubkey" >> "$authorized_keys_file"
			done
		fi
		"$sshd_bin"
	fi
	chown -R korobas:korobas "$home_dir"
	exec gosu korobas "$0" "$@"
fi

export HOME="$home_dir"

mkdir -p \
	"$home_dir/.cache/mise" \
	"$home_dir/.local/state/korobas" \
	"$home_dir/.local/state/mise" \
	"$home_dir/.local/share/mise"

if [ ! -d "$home_dir/.dotfiles" ] && [ -d "$template_dir/.dotfiles" ]; then
	cp -a "$template_dir/.dotfiles" "$home_dir/.dotfiles"
fi

if [ -d "$home_dir/.dotfiles" ]; then
	stow -d "$home_dir/.dotfiles" -t "$home_dir" .
fi

if [ ! -f "$bootstrap_marker" ]; then
	mise install --jobs=1
	mise run install --jobs=1
	touch "$bootstrap_marker"
fi

if [ -z "${1:-}" ]; then
	exec sleep infinity
fi

exec "$@"
