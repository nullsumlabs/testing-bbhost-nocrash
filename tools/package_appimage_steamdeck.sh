#!/bin/bash
# The Steam Deck's AppImage: the Linux one (tools/package_appimage.sh) with the
# Deck's settings - tools/steamdeck/bbhost-steamdeck.toml, its screen's
# 1280x800 full screen at the game's own 30 fps, and STEAMDECK.md - and, when
# BB_APPIMAGE_BUILD=1 builds it, compiled for the Deck's CPU: -march=znver2,
# which is what both Deck revisions are (Van Gogh and Sephiroth are Zen 2).
# The game's paths are not in it, as in every package: the per-user config
# holds those, so the Deck and a PC can share them.
#
#   tools/package_appimage_steamdeck.sh [INPUT] [OUTDIR]
#
# INPUT, OUTDIR and the switches are tools/package_appimage.sh's, plus
# BB_MARCH, which defaults to znver2 here (an empty BB_MARCH builds for the
# compiler's own target, as the plain Linux AppImage does).
#
# On a Deck: run the .AppImage, or add that file to Steam as a non-Steam game
# (Desktop Mode, Games, Add a Non-Steam Game) and start it from Game Mode.
# Running an AppImage needs FUSE, and "Cannot mount the AppImage, please check
# your FUSE setup" (or a missing libfuse.so.2) is what it says where that is
# not there - the Deck and Steam's own runtime both being known for it. Then
# put --appimage-extract-and-run among the game's launch options in Steam: the
# runtime unpacks itself into /tmp and runs from there. STEAMDECK.md has the
# rest (the controller layout, 30 or 60 fps, the first area's shader compile).
set -eu
cd "$(dirname "$0")"
BB_APPIMAGE_PROFILE=steamdeck BB_MARCH=${BB_MARCH-znver2} exec ./package_appimage.sh "$@"
