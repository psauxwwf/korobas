#!/bin/sh
set -eu

home_dir=/home/korobas
template_dir=/usr/local/share/korobas-home

if [ "$(id -u)" -eq 0 ]; then
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
	chown -R korobas:korobas "$home_dir"
	"$sshd_bin"
	exec gosu korobas "$0" "$@"
fi

mkdir -p \
	"$home_dir/.cache/mise" \
	"$home_dir/.local/state/mise" \
	"$home_dir/.local/share/mise"

if [ ! -d "$home_dir/.dotfiles" ] && [ -d "$template_dir/.dotfiles" ]; then
	cp -a "$template_dir/.dotfiles" "$home_dir/.dotfiles"
fi

if [ -d "$home_dir/.dotfiles" ]; then
	stow -d "$home_dir/.dotfiles" -t "$home_dir" .
fi

# MISE_JOBS=1 mise install

exec "$@"
