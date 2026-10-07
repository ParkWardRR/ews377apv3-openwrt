#!/usr/bin/env bash
set -euo pipefail

# Multi-SKU web-ui image builder for the EnGenius ap-hk07 family.
# Produces three Senao-headed .bin files from a single OpenWrt payload,
# one per SKU (EWS377APv3, ECW230v3, EWS377-FIT), differing only in
# the 4-byte product_id at header offset 0x08.
#
# Usage:
#   ./scripts/build-release.sh <web-ui-factory.bin> [output-dir]
#
# Requires: quarry (from pelegrun-ap-hk07-firmware-tools)
#   Install: cargo build --release -p quarry
#   Repo:    https://github.com/ParkWardRR/pelegrun-ap-hk07-firmware-tools

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

declare -A SKUS=(
    [ews377apv3]=282
    [ecw230v3]=284
    [ews377fit]=300
)

SKU_ORDER=(ews377apv3 ecw230v3 ews377fit)

usage() {
    cat <<EOF
Usage: $(basename "$0") <web-ui-factory.bin> [output-dir]

Arguments:
  web-ui-factory.bin   The source image (must have a valid Senao header)
  output-dir           Where to write output files (default: ./release)

The source image's product_id does not matter — each output is reheaded
to the correct value. The OpenWrt payload is identical in all three.

Options:
  -h, --help           Show this help
  --skip-ubi-verify    Skip the factory.ubi config@hk07 verification step
  --ubi <factory.ubi>  Also verify a factory.ubi before building (recommended)
EOF
    exit 0
}

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ✓\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m  ✗\033[0m %s\n' "$*" >&2; exit 1; }
warn() { printf '\033[1;33m  !\033[0m %s\n' "$*"; }

SKIP_UBI_VERIFY=false
UBI_FILE=""
SOURCE=""
OUTDIR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage ;;
        --skip-ubi-verify) SKIP_UBI_VERIFY=true; shift ;;
        --ubi) UBI_FILE="$2"; shift 2 ;;
        -*) fail "Unknown option: $1" ;;
        *)
            if [[ -z "$SOURCE" ]]; then
                SOURCE="$1"
            elif [[ -z "$OUTDIR" ]]; then
                OUTDIR="$1"
            else
                fail "Unexpected argument: $1"
            fi
            shift
            ;;
    esac
done

[[ -n "$SOURCE" ]] || { usage; }
[[ -f "$SOURCE" ]] || fail "Source image not found: $SOURCE"
OUTDIR="${OUTDIR:-./release}"

if ! command -v quarry &>/dev/null; then
    fail "quarry not found in PATH. Install from https://github.com/ParkWardRR/pelegrun-ap-hk07-firmware-tools"
fi

mkdir -p "$OUTDIR"

# --- Step 0: Verify factory.ubi contains config@hk07 (if provided) ---

if [[ -n "$UBI_FILE" ]]; then
    log "Verifying config@hk07 in $UBI_FILE"
    if quarry verify-ubi "$UBI_FILE" --board hk07; then
        ok "config@hk07 present — safe to ship"
    else
        fail "config@hk07 NOT found in $UBI_FILE — do NOT ship this image"
    fi
elif [[ "$SKIP_UBI_VERIFY" == false ]]; then
    warn "No --ubi <factory.ubi> provided. Pass one to verify config@hk07, or use --skip-ubi-verify."
fi

# --- Step 1: Inspect source image ---

log "Inspecting source image: $SOURCE"
quarry inspect "$SOURCE" || fail "Source image has invalid Senao header"
echo

# --- Step 2: Build per-SKU images ---

PREFIX=$(basename "$SOURCE" .bin)
PREFIX=${PREFIX%-web-ui-factory}
PREFIX=${PREFIX%-web-ui-ews377apv3}
PREFIX=${PREFIX%-web-ui-ecw230v3}
PREFIX=${PREFIX%-web-ui-ews377fit}

log "Building per-SKU images in $OUTDIR/"

for sku in "${SKU_ORDER[@]}"; do
    pid=${SKUS[$sku]}
    outfile="$OUTDIR/${PREFIX}-web-ui-${sku}.bin"

    quarry rehead "$SOURCE" "$outfile" --to "$pid"
    ok "$sku (product_id $pid) → $(basename "$outfile")"
done
echo

# --- Step 3: Verify all outputs ---

log "Verifying all output images"
VERIFY_PASS=true

for sku in "${SKU_ORDER[@]}"; do
    pid=${SKUS[$sku]}
    outfile="$OUTDIR/${PREFIX}-web-ui-${sku}.bin"

    if ! [[ -f "$outfile" ]]; then
        fail "Missing output: $outfile"
    fi

    actual_pid=$(quarry inspect "$outfile" 2>/dev/null | grep -i 'product_id' | awk '{print $NF}')

    if [[ "$actual_pid" == "$pid" ]]; then
        ok "$sku: product_id = $actual_pid"
    else
        printf '\033[1;31m  ✗\033[0m %s: expected product_id %s, got %s\n' "$sku" "$pid" "$actual_pid" >&2
        VERIFY_PASS=false
    fi
done
echo

[[ "$VERIFY_PASS" == true ]] || fail "Verification failed — check output above"

# --- Step 4: Generate SHA256SUMS ---

log "Generating SHA256SUMS"
(cd "$OUTDIR" && sha256sum -- *.bin > SHA256SUMS)
ok "SHA256SUMS written to $OUTDIR/SHA256SUMS"

cat "$OUTDIR/SHA256SUMS"
echo

# --- Done ---

log "Release artifacts ready in $OUTDIR/"
for sku in "${SKU_ORDER[@]}"; do
    pid=${SKUS[$sku]}
    outfile="$OUTDIR/${PREFIX}-web-ui-${sku}.bin"
    printf '  %-40s  product_id %-3s  (%s)\n' "$(basename "$outfile")" "$pid" "$sku"
done
echo
log "Next: include factory.ubi, sysupgrade.bin, and initramfs-uImage.itb alongside these."
