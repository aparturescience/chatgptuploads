#!/bin/bash
#
# make_vendor_min.sh - put the brightness adaptor INTO a vendor image and make
# the new image as small as possible.
#
#   ./make_vendor_min.sh SRC_VENDOR_IMG OUT_VENDOR_IMG EXTRAS_DIR [SLACK_MB]
#
#   SRC_VENDOR_IMG  your current vendor image (ext4; raw or Android-sparse)
#   OUT_VENDOR_IMG  new image to create, e.g. vendorN.img
#   EXTRAS_DIR      folder that contains vendor/bin/obright_service and
#                   vendor/etc/init/obright_service.rc
#                   (Brightness_fix_originos/hardcoded)
#   SLACK_MB        free space left in the new image (default 4). Use 0 for the
#                   absolute minimum; with a read-only /vendor it is not needed
#                   at run time, but a later edit from recovery needs some.
#
# Needs (WSL/Ubuntu):  sudo apt install e2fsprogs rsync attr android-sdk-libsparse-utils
# Keep your original image as a backup. Nothing here modifies SRC_VENDOR_IMG.
#
set -u

SRC="${1:-}"; OUT="${2:-}"; EXTRAS="${3:-}"; SLACK="${4:-4}"
if [ -z "$SRC" ] || [ -z "$OUT" ] || [ -z "$EXTRAS" ]; then
    sed -n '2,19p' "$0"; exit 1
fi
[ -f "$SRC" ] || { echo "Source image not found: $SRC"; exit 1; }
for f in vendor/bin/obright_service vendor/etc/init/obright_service.rc; do
    [ -f "$EXTRAS/$f" ] || { echo "Missing $EXTRAS/$f"; exit 1; }
done
for t in rsync setfattr getfattr mke2fs e2fsck resize2fs dumpe2fs findmnt; do
    command -v "$t" >/dev/null || { echo "Missing tool: $t  (sudo apt install e2fsprogs rsync attr)"; exit 1; }
done
case "$SLACK" in ''|*[!0-9]*) echo "SLACK_MB must be a number"; exit 1 ;; esac

SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"
$SUDO true || exit 1

WORK=$(mktemp -d "${TMPDIR:-/tmp}/vendormin.XXXXXX")
SM="$WORK/src"; DM="$WORK/dst"; mkdir -p "$SM" "$DM"
TMPOUT="$OUT.tmp"

cleanup() {
    mountpoint -q "$SM" 2>/dev/null && $SUDO umount "$SM"
    mountpoint -q "$DM" 2>/dev/null && $SUDO umount "$DM"
    rm -rf "$WORK"
}
trap cleanup EXIT

die() { echo "ERROR: $*"; rm -f "$TMPOUT"; exit 1; }

# ---- 0. source image -------------------------------------------------------
SRCRAW="$SRC"
if file "$SRC" | grep -qi "sparse"; then
    command -v simg2img >/dev/null || die "sparse image: sudo apt install android-sdk-libsparse-utils"
    echo "== converting sparse image"
    simg2img "$SRC" "$WORK/src.raw" || die "simg2img failed"
    SRCRAW="$WORK/src.raw"
fi
file "$SRCRAW" | grep -qi "ext[234] filesystem" || die "source is not an ext2/3/4 image: $(file -b "$SRCRAW" | cut -c1-80)"
echo "== checking source filesystem (read-only)"
$SUDO e2fsck -fn "$SRCRAW" >/dev/null 2>&1 || die "source image does not pass e2fsck -fn; fix or re-extract it first"

$SUDO mount -o loop,ro "$SRCRAW" "$SM" || die "cannot mount source"
USED=$(df -B1 --output=used "$SM" | tail -1 | tr -d ' ')
INODES=$($SUDO find "$SM" -xdev | wc -l)
ISIZE=$(dumpe2fs -h "$SRCRAW" 2>/dev/null | awk '/^Inode size/ {print $3}')
case "$ISIZE" in ''|*[!0-9]*) ISIZE=256 ;; esac
echo "   used: $((USED/1048576)) MiB   entries: $INODES   inode size: $ISIZE"

# ---- 1. fresh, roomy image (it is shrunk afterwards) -------------------------
INIT_MB=$(( USED/1048576 * 115 / 100 + 32 ))
NINODES=$(( INODES + 600 ))
rm -f "$TMPOUT"
truncate -s "${INIT_MB}M" "$TMPOUT" || die "cannot create $TMPOUT"
echo "== creating image: ${INIT_MB} MiB (temporary), $NINODES inodes"
$SUDO mke2fs -q -t ext4 -b 4096 -m 0 -N "$NINODES" -I "$ISIZE" -O ^has_journal -L vendor "$TMPOUT" || die "mke2fs failed"
$SUDO mount -o loop,rw "$TMPOUT" "$DM" || die "cannot mount new image"
DEVN=$(basename "$(findmnt -n -o SOURCE "$DM")")
[ -w "/sys/fs/ext4/$DEVN/reserved_clusters" ] && echo 0 | $SUDO tee "/sys/fs/ext4/$DEVN/reserved_clusters" >/dev/null

# ---- 2. copy everything (xattrs = SELinux labels, hard links, owners) -------
echo "== copying (this takes a minute)"
$SUDO rsync -aHX --numeric-ids "$SM"/ "$DM"/
RC=$?
[ $RC -eq 0 ] || die "rsync reported errors (code $RC)"

# ---- 3. add the adaptor with proper owner, mode and SELinux label ------------
echo "== adding the brightness adaptor"
$SUDO mkdir -p "$DM/bin" "$DM/etc/init"
$SUDO install -m 0755 -o 0 -g 2000 "$EXTRAS/vendor/bin/obright_service" "$DM/bin/obright_service" || die "install bin"
$SUDO setfattr -n security.selinux -v "u:object_r:vendor_file:s0" "$DM/bin/obright_service" || die "label bin"
$SUDO install -m 0644 -o 0 -g 0 "$EXTRAS/vendor/etc/init/obright_service.rc" "$DM/etc/init/obright_service.rc" || die "install rc"
$SUDO setfattr -n security.selinux -v "u:object_r:vendor_configs_file:s0" "$DM/etc/init/obright_service.rc" || die "label rc"
echo "   neighbour labels for comparison:"
for n in "$DM"/etc/init/*.rc; do
    [ "$n" = "$DM/etc/init/obright_service.rc" ] && continue
    $SUDO getfattr -n security.selinux --only-values "$n" 2>/dev/null | tr -d '\0' | sed "s|^|     $(basename "$n"): |"; echo; break
done

$SUDO sync
$SUDO umount "$DM" || die "umount new image"
$SUDO umount "$SM" || die "umount source"

# ---- 4. shrink to the minimum, then add the requested slack ------------------
echo "== checking and shrinking"
$SUDO e2fsck -fy "$TMPOUT" >/dev/null 2>&1
for i in 1 2 3; do
    BEFORE=$(dumpe2fs -h "$TMPOUT" 2>/dev/null | awk '/^Block count/ {print $3}')
    $SUDO resize2fs -M "$TMPOUT" >/dev/null 2>&1 || die "resize2fs -M failed"
    AFTER=$(dumpe2fs -h "$TMPOUT" 2>/dev/null | awk '/^Block count/ {print $3}')
    [ "$AFTER" = "$BEFORE" ] && break
done
BS=$(dumpe2fs -h "$TMPOUT" 2>/dev/null | awk '/^Block size/ {print $3}')
BLK=$(dumpe2fs -h "$TMPOUT" 2>/dev/null | awk '/^Block count/ {print $3}')
TARGET=$(( BLK + SLACK * 1048576 / BS ))
truncate -s $(( TARGET * BS )) "$TMPOUT" || die "truncate"
if [ "$SLACK" -gt 0 ]; then
    $SUDO resize2fs "$TMPOUT" "$TARGET" >/dev/null 2>&1 || die "resize2fs (slack) failed"
fi
$SUDO e2fsck -fy "$TMPOUT" >/dev/null 2>&1
$SUDO e2fsck -fn "$TMPOUT" >/dev/null 2>&1 || die "final e2fsck is not clean"

# ---- 5. verify -----------------------------------------------------------------
echo "== verifying"
$SUDO mount -o loop,ro "$TMPOUT" "$DM" || die "cannot mount result"
$SUDO mount -o loop,ro "$SRCRAW" "$SM" || die "cannot mount source again"
ls -l "$DM/bin/obright_service" "$DM/etc/init/obright_service.rc"
echo "   files that differ from the source listing (expect only the two new ones):"
diff <(cd "$SM" && $SUDO find . | sort) <(cd "$DM" && $SUDO find . | sort) | sed 's/^/     /'
echo "   labels:"
for f in bin/obright_service etc/init/obright_service.rc; do
    printf '     %s  ' "$f"; $SUDO getfattr -n security.selinux --only-values "$DM/$f" | tr -d '\0'; echo
done
df -h "$DM" | tail -1
$SUDO umount "$DM"; $SUDO umount "$SM"

mv -f "$TMPOUT" "$OUT"
echo
echo "== done"
ls -l "$OUT"
dumpe2fs -h "$OUT" 2>/dev/null | grep -E "Block count|Free blocks|Inode count|Free inodes"
echo "Source size: $(stat -c %s "$SRC") bytes  ->  new size: $(stat -c %s "$OUT") bytes"
echo "Flash it like before (fastboot flash vendor $OUT) and keep vbmeta verification disabled."
