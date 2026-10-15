#!/bin/bash
# An AppImage of bbhost: one file to run, nothing to install and nothing to
# unpack - run it, or hand it to Steam as a non-Steam game. It packs the Linux
# package (tools/package_linux.sh's tarball) rather than the bare binary, so
# what that carries comes with it: the patch manifests (patches/), the official
# plugins, bbhost.example.toml, the launcher and the README.
#
#   tools/package_appimage.sh [INPUT] [OUTDIR]
#     INPUT   a tarball from tools/package_linux.sh, or a bbhost binary (which
#             is packed into that tarball first). Default: the newest tarball
#             in build/linux.
#     OUTDIR  default build/appimage
#
#   BB_APPIMAGE_BUILD=1   build before packing: CI_PORTABLE=1 tools/ci_build.sh
#                         (both build scripts already run one job per core),
#                         then tools/package_linux.sh build-ci/build/bbhost.
#                         CI_WORK and CI_APT are passed on as they are.
#   BB_MARCH=<token>      what that build compiles for: one -march token, e.g.
#                         znver2 or native. Empty here, the compiler's own
#                         target, which is what an AppImage for other machines
#                         wants; see tools/package_appimage_steamdeck.sh for
#                         the one that sets it.
#   BB_APPIMAGE_PROFILE=steamdeck
#                         the Deck's settings (tools/steamdeck): its 1280x800
#                         full-screen 30 fps bbhost-steamdeck.toml, STEAMDECK.md,
#                         and AppRun pointed at that config. Anything else is
#                         the plain Linux one.
#   APPIMAGETOOL=<path>   use this appimagetool instead of fetching one
#   APPIMAGETOOL_RUNTIME=<path>
#                         the AppImage runtime to embed. Without it
#                         appimagetool downloads the current one, so packing
#                         needs network access.
#   APPIMAGETOOL_URL, APPIMAGETOOL_SHA256
#                         where to fetch appimagetool from, and what its sha256
#                         has to be. Its continuous build changes, so nothing
#                         is pinned unless you set the hash.
#
# An AppImage is mounted read-only, so a session's log and an F12 frame dump
# cannot go beside the binary the way the tarball's launcher puts them: AppRun
# writes them under ${XDG_DATA_HOME:-~/.local/share}/bbhost/logs instead. The
# per-user config, the saves and the shader caches are where they are for every
# other bbhost, so an AppImage and an installed copy share them.
set -eu
cd "$(dirname "$0")/.."
SRC=$PWD
profile=${BB_APPIMAGE_PROFILE:-linux}
case "$profile" in
    linux | steamdeck) ;;
    *) echo "unknown BB_APPIMAGE_PROFILE=$profile (linux, steamdeck)"; exit 1 ;;
esac
out=$(realpath -m "${2:-build/appimage}")
mkdir -p "$out"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

if [ "${BB_APPIMAGE_BUILD:-0}" = 1 ]; then
    extra=""
    if [ -n "${BB_MARCH:-}" ]; then
        extra="-DCMAKE_C_FLAGS=-march=$BB_MARCH -DCMAKE_CXX_FLAGS=-march=$BB_MARCH"
        echo "appimage: building (CI_PORTABLE, -march=$BB_MARCH)"
    else
        echo "appimage: building (CI_PORTABLE, the compiler's own target)"
    fi
    CI_PORTABLE=1 CI_CMAKE_ARGS="${CI_CMAKE_ARGS:-} $extra" tools/ci_build.sh
    tools/package_linux.sh "${CI_WORK:-$SRC/build-ci}/build/bbhost" build/linux
fi

input=${1:-}
if [ -z "$input" ]; then
    input=$(ls -1t build/linux/bbhost-linux-*.tar.gz 2>/dev/null | head -1 || true)
fi
if [ -z "$input" ] || [ ! -e "$input" ]; then
    echo "nothing to pack: pass tools/package_linux.sh's tarball or a bbhost binary, or set"
    echo "BB_APPIMAGE_BUILD=1 to build one (no tarball in build/linux)"
    exit 1
fi

mkdir -p "$work/pkg"
case "$input" in
    *.tar.gz | *.tgz)
        cp "$input" "$work/pkg.tgz"
        ;;
    *)
        # A binary: the Linux package is what knows how to lay a bbhost out
        # (the manifests, the plugins, the launcher), so build one from it.
        [ -x "$input" ] || { echo "$input is neither a .tar.gz nor an executable"; exit 1; }
        tools/package_linux.sh "$input" "$work/linux"
        cp "$work"/linux/bbhost-linux-*.tar.gz "$work/pkg.tgz"
        ;;
esac
tar xzf "$work/pkg.tgz" -C "$work/pkg"
pkg=$(ls -d "$work"/pkg/bbhost-linux-* 2>/dev/null | head -1)
[ -n "$pkg" ] || { echo "the package has no bbhost-linux-* folder"; exit 1; }

base=$(basename "$pkg")
name=$base
if [ "$profile" = steamdeck ]; then
    name=${base/bbhost-linux-/bbhost-steamdeck-}
fi
appdir=$work/$name.AppDir
mkdir -p "$appdir"
cp -r "$pkg"/. "$appdir"/
# The tarball's write targets (the run fills them): a mounted AppImage cannot,
# and AppRun sends those writes somewhere writable instead.
rm -rf "$appdir/data" "$appdir/logs" "$appdir/build"

if [ "$profile" = steamdeck ]; then
    cp tools/steamdeck/bbhost-steamdeck.toml tools/steamdeck/STEAMDECK.md "$appdir"/
    # The same edit tools/package_steamdeck.sh makes, so an extracted AppImage's
    # launcher uses the Deck's settings too.
    sed -i 's/^cfg=\${BBHOST_CONFIG:-bbhost.toml}/cfg=${BBHOST_CONFIG:-bbhost-steamdeck.toml}/' "$appdir/run-bbhost.sh"
    grep -q 'bbhost-steamdeck.toml' "$appdir/run-bbhost.sh" ||
        { echo "run-bbhost.sh: config line not found"; exit 1; }
fi

cat > "$appdir/AppRun" <<'EOF'
#!/bin/bash
# AppRun: starts bbhost out of the mounted AppImage. The image is read-only, so
# the session's log goes to ${XDG_DATA_HOME:-~/.local/share}/bbhost/logs (the
# newest ten are kept) and an F12 frame dump to a folder of its own there.
# Arguments are passed on, so --setup works.
set -o pipefail
here=${APPDIR:-$(cd "$(dirname "$0")" && pwd)}
data=${XDG_DATA_HOME:-$HOME/.local/share}/bbhost
mkdir -p "$data/logs"
log=$data/logs/bbhost-$(date +%Y%m%d-%H%M%S).log
ls -1t "$data"/logs/bbhost-*.log 2>/dev/null | tail -n +10 | xargs -r rm -f
cfg=${BBHOST_CONFIG:-}
if [ -z "$cfg" ] && [ -f "$here/bbhost-steamdeck.toml" ]; then
    cfg=$here/bbhost-steamdeck.toml
fi
args=()
if [ -n "$cfg" ]; then args=(--config "$cfg"); fi
export BBHOST_CAPTURE_DIR=${BBHOST_CAPTURE_DIR:-$data/f12}
cd "$here" || exit 1
echo "bbhost: AppImage, config ${cfg:-the per-user one}, log $log"
# tee -i: Ctrl-C stops the game, not the log, so its last lines are kept.
./bbhost "${args[@]}" "$@" 2>&1 | tee -i "$log"
exit "${PIPESTATUS[0]}"
EOF

if [ "$profile" = steamdeck ]; then
    title="bbhost (Steam Deck)"
    comment="Bloodborne on PC: bbhost with the Steam Deck's settings"
else
    title="bbhost"
    comment="Bloodborne on PC with bbhost: the game's own 1.09 executable on Vulkan"
fi
cat > "$appdir/bbhost.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$title
Comment=$comment
Exec=bbhost
Icon=bbhost
Terminal=false
Categories=Game;
EOF

# The icon: the 256x256 image inside res/bbhost.ico, taken out of it as it is
# (the AppImage spec's .DirIcon is that same file, 256x256 PNG).
python3 - "$SRC/res/bbhost.ico" "$appdir/bbhost.png" <<'PY'
import struct, sys
d = open(sys.argv[1], 'rb').read()
if d[:4] != b'\x00\x00\x01\x00':
    sys.exit(f'{sys.argv[1]}: not an ICO')
best = None
for i in range(struct.unpack('<H', d[4:6])[0]):
    w, h, c, r, planes, bpp, size, off = struct.unpack('<BBBBHHII', d[6 + 16 * i:22 + 16 * i])
    if d[off:off + 8] == b'\x89PNG\r\n\x1a\n' and (best is None or size > best[0]):
        best = (size, off)
if best is None:
    sys.exit(f'{sys.argv[1]}: no PNG image in it to use as the AppImage icon')
open(sys.argv[2], 'wb').write(d[best[1]:best[1] + best[0]])
PY
cp "$appdir/bbhost.png" "$appdir/.DirIcon"

# Plain modes (a filesystem without them would send every file out executable).
find "$appdir" -type d -exec chmod 755 {} +
find "$appdir" -type f -exec chmod 644 {} +
chmod 755 "$appdir/bbhost" "$appdir/AppRun"
[ -f "$appdir/run-bbhost.sh" ] && chmod 755 "$appdir/run-bbhost.sh"

tool=${APPIMAGETOOL:-}
if [ -z "$tool" ]; then
    tool=$work/appimagetool-x86_64.AppImage
    url=${APPIMAGETOOL_URL:-https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage}
    echo "appimage: fetching appimagetool"
    curl -sSL -m 600 -o "$tool" "$url"
    chmod 755 "$tool"
    sum=$(sha256sum "$tool" | cut -d' ' -f1)
    if [ -n "${APPIMAGETOOL_SHA256:-}" ]; then
        [ "$sum" = "$APPIMAGETOOL_SHA256" ] ||
            { echo "appimagetool: sha256 $sum is not APPIMAGETOOL_SHA256"; exit 1; }
        echo "appimage: appimagetool sha256 ok"
    else
        echo "appimage: appimagetool sha256 $sum (set APPIMAGETOOL_SHA256 to pin it)"
    fi
fi
[ -x "$tool" ] || { echo "appimagetool: $tool is not executable"; exit 1; }

dest=$out/$name.AppImage
rm -f "$dest"
args=(-n)  # no AppStream metadata in here
if [ -n "${APPIMAGETOOL_RUNTIME:-}" ]; then args+=(--runtime-file "$APPIMAGETOOL_RUNTIME"); fi
# appimagetool is itself an AppImage: APPIMAGE_EXTRACT_AND_RUN runs it without
# FUSE, which a server or a container usually does not have.
ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "$tool" "${args[@]}" "$appdir" "$dest"
echo "appimage: $dest ($(( $(stat -c %s "$dest") / 1048576 )) MB)"
