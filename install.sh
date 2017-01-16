#!/usr/bin/env bash
set -u

DESTDIR=${XDG_CONFIG_HOME:-${HOME}/.config}/mpv/scripts

rocks=(luasocket luasec lunajson)
src=(twitch-chat.lua)

for rock in ${rocks[@]}; do
	luarocks --local show ${rock} >/dev/null 2>/dev/null
	if [[ $? != 0 ]]; then
		luarocks --local install ${rock}
	fi
done

mkdir -p "${DESTDIR}"
rsync -avx ${src[@]} "${DESTDIR}/"
