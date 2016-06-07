#!/usr/bin/env bash
set -eu

DESTDIR=${XDG_CONFIG_HOME:-${HOME}/.config}/mpv/scripts

rocks=(luasocket luasec lunajson)
src=(twitch-chat.lua)

for rock in ${rocks[@]}; do
	luarocks-5.2 --local show ${rock} 2>&1 >/dev/null
	if [[ $? != 0 ]]; then
		luarocks-5.2 --local install ${rock}
	fi
done

mkdir -p "${DESTDIR}"
rsync -avx ${src[@]} "${DESTDIR}/"
