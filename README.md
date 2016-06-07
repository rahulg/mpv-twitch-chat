# mpv-twitch-chat

Displays Twitch.tv chat replay when watching VoDs with mpv.

# Installation

## Prerequisites

- Install `mpv` and `lua`
- Install `luarocks-5.2` (or 5.1 if your `mpv` uses that instead) with your package manager of choice
	- OS X: `brew install lua`
	- Arch Linux: `pacman -S luarocks5.2`
- `luarocks-5.2 --local install luasocket`
- `luarocks-5.2 --local install luasec`
- `luarocks-5.2 --local install lunajson`

## Script

- `mkdir -p ~/.config/mpv/scripts`
- `cp twitch-chat.lua ~/.config/mpv/scripts`
