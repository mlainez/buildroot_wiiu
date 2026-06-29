#!/usr/bin/env bash
# Build a per-console fw.img from the linux-loader submodule.
#
# Reads STARBUCK_KEY and STARBUCK_IV (32 hex chars each) from the environment
# or <repo>/secrets.env. Without them it exits 0 (the build falls back to the
# committed common-key fw.img). $1 = BINARIES_DIR (default <repo>/output/images);
# result is written to $BINARIES_DIR/sd/fw.img.
#
# Build backend, in order: devkitARM ($DEVKITARM), podman, docker.

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BINARIES_DIR="${1:-$REPO_ROOT/output/images}"
SECRETS_FILE="$REPO_ROOT/secrets.env"
LOADER_SRC="$REPO_ROOT/linux-loader"
LOADER_BUILD="$(dirname "$BINARIES_DIR")/build/linux-loader-fw"
CI_IMAGE="registry.gitlab.com/linux-wiiu/linux-loader/ci"

info() { printf '[fw.img] %s\n' "$*"; }
skip() { info "$*"; exit 0; }
die()  { printf '[fw.img] ERROR: %s\n' "$*" >&2; exit 1; }

# --- 1. Load keys (env wins; secrets.env supplements) ----------------------
if [ -f "$SECRETS_FILE" ]; then
  # shellcheck disable=SC1090
  set -a; . "$SECRETS_FILE"; set +a
fi

if [ -z "${STARBUCK_KEY:-}" ] || [ -z "${STARBUCK_IV:-}" ]; then
  cat <<EOF
[fw.img] STARBUCK_KEY / STARBUCK_IV not set — skipping fw.img build.

  To enable, copy your console's OTP key + IV into a secrets.env file:

      cp secrets.env.example secrets.env
      \$EDITOR secrets.env       # paste your two 32-hex-char values

  Then re-run the build (or just \`board/wiiu/build-fw-img.sh\`).
  See README.md for how to dump them with Dumpling.
EOF
  exit 0
fi

# --- 2. Validate format ----------------------------------------------------
hex32='^[0-9A-Fa-f]{32}$'
echo "$STARBUCK_KEY" | grep -qE "$hex32" \
  || die "STARBUCK_KEY must be exactly 32 hex chars (got: ${#STARBUCK_KEY} chars)"
echo "$STARBUCK_IV"  | grep -qE "$hex32" \
  || die "STARBUCK_IV must be exactly 32 hex chars (got: ${#STARBUCK_IV} chars)"

STARBUCK_KEY_UP="$(echo "$STARBUCK_KEY" | tr 'a-f' 'A-F')"
STARBUCK_IV_UP="$(echo "$STARBUCK_IV"  | tr 'a-f' 'A-F')"

# --- 3. Stage a clean copy of linux-loader (don't dirty the submodule) -----
[ -d "$LOADER_SRC" ] \
  || die "linux-loader submodule missing — run: git submodule update --init linux-loader"
[ -f "$LOADER_SRC/castify.py" ] \
  || die "linux-loader/castify.py not found — submodule may not be checked out"

info "Staging build copy at $LOADER_BUILD"
rm -rf "$LOADER_BUILD"
mkdir -p "$LOADER_BUILD"
rsync -a --exclude='.git' "$LOADER_SRC/" "$LOADER_BUILD/"

info "Substituting Starbuck key + IV into castify.py"
sed -i "s/B5XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX/${STARBUCK_KEY_UP}/g" "$LOADER_BUILD/castify.py"
sed -i "s/91XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX/${STARBUCK_IV_UP}/g" "$LOADER_BUILD/castify.py"

# Cheap leak check — secrets must not survive into the repo working tree.
grep -q 'B5XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX' "$LOADER_BUILD/castify.py" \
  && die "key substitution failed; refusing to build with placeholder"

# --- 4. Pick a backend ----------------------------------------------------
JOBS="$(nproc 2>/dev/null || echo 4)"

build_native() {
  info "Building via native devkitARM ($DEVKITARM)"
  ( cd "$LOADER_BUILD" && make -j"$JOBS" )
}

build_podman() {
  info "Building via podman ($CI_IMAGE)"
  podman run --rm -v "$LOADER_BUILD:/app:Z" -w /app "$CI_IMAGE"
}

build_docker() {
  info "Building via docker ($CI_IMAGE)"
  docker run --rm -v "$LOADER_BUILD:/app" -w /app "$CI_IMAGE"
}

if [ -n "${DEVKITARM:-}" ] && [ -d "$DEVKITARM" ]; then
  build_native
elif command -v podman >/dev/null 2>&1; then
  build_podman
elif command -v docker >/dev/null 2>&1; then
  build_docker
else
  cat >&2 <<EOF
[fw.img] ERROR: no backend available to build fw.img.
  Install podman or docker, or install devkitARM and export DEVKITARM=<path>,
  then re-run board/wiiu/build-fw-img.sh.
EOF
  exit 1
fi

# --- 5. Stage the artifact -------------------------------------------------
[ -f "$LOADER_BUILD/fw.img" ] \
  || die "build finished but $LOADER_BUILD/fw.img was not produced"

mkdir -p "$BINARIES_DIR/sd"
cp "$LOADER_BUILD/fw.img" "$BINARIES_DIR/sd/fw.img"

info "fw.img staged at $BINARIES_DIR/sd/fw.img"
info "Full SD layout ready under $BINARIES_DIR/sd/"
