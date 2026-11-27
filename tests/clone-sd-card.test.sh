#!/bin/bash
# Tests for clone-sd-card.sh against a fake installed card built from disk
# images. Needs a Mac with e2fsprogs, no SD card and no password.
#   bash tests/clone-sd-card.test.sh
#
# Not covered: the raw write to a real card and the read back check, because
# both need root.

set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CLONE="$REPO/clone-sd-card.sh"
E2=""
for dir in /opt/homebrew/opt/e2fsprogs/sbin /usr/local/opt/e2fsprogs/sbin; do
    [ -x "$dir/debugfs" ] && E2="$dir" && break
done
if [ "$(uname)" != Darwin ] || [ -z "$E2" ]; then
    echo "SKIP: needs macOS with e2fsprogs (brew install e2fsprogs)"
    exit 0
fi

WORK="$(cd "$(mktemp -d)" && pwd -P)"
DEV=""
# Detach by image path, not by a remembered disk number. A number can be
# reused by a real disk once the image is gone.
cleanup() {
    hdiutil info | awk -v work="$WORK/" '
        /^image-path/ { ours = index($0, work) > 0 }
        ours && /^\/dev\/disk[0-9]+[[:space:]]/ { print $1 }
    ' | while read -r dev; do
        hdiutil detach "$dev" -force >/dev/null 2>&1
    done
    rm -rf "$WORK"
}
trap cleanup EXIT
PASS=0
FAIL=0
IMG="$WORK/store/station.img"
HOOK="- [ bash, /boot/firmware/printer-test-rig/firstBootInstall.sh, arm ]"
P1_START=16384
P1_SIZE=131072
P2_START=147456
CARD_MB=400
OFF=$((P2_START * 512))

ok() { PASS=$((PASS + 1)); echo "ok    $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL  $1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
le32() {
    # shellcheck disable=SC2059
    printf "$(printf '\\x%02x\\x%02x\\x%02x\\x%02x' $(($1 & 255)) $((($1 >> 8) & 255)) $((($1 >> 16) & 255)) $((($1 >> 24) & 255)))"
}
attach() {
    hdiutil attach -imagekey diskimage-class=CRawDiskImage -nomount "$1" | awk 'NR == 1 { print $1 }'
}
rootcat() { "$E2/debugfs" -R "cat $2" "$1?offset=$OFF" 2>/dev/null; }
blobsum() { "$E2/debugfs" -R "cat /data/blob" "$1?offset=$OFF" 2>/dev/null | shasum | awk '{ print $1 }'; }

echo "Building a fake installed card..."
CARD="$WORK/card.img"
P2_SIZE=$((CARD_MB * 2048 - P2_START))
dd if=/dev/null of="$CARD" bs=1m seek="$CARD_MB" 2>/dev/null
{
    printf '\x00\x00\x00\x00\x0c\x00\x00\x00'; le32 "$P1_START"; le32 "$P1_SIZE"
    printf '\x00\x00\x00\x00\x83\x00\x00\x00'; le32 "$P2_START"; le32 "$P2_SIZE"
} | dd of="$CARD" bs=1 seek=446 conv=notrunc 2>/dev/null
printf '\x55\xaa' | dd of="$CARD" bs=1 seek=510 conv=notrunc 2>/dev/null

mkdir -p "$WORK/root/etc" "$WORK/root/data" "$WORK/root/home/pi/printer-test-rig"
echo "PR-TEST-RIG-9" > "$WORK/root/etc/hostname"
printf '127.0.0.1\tlocalhost\n::1\t\tlocalhost ip6-localhost\n127.0.1.1\tPR-TEST-RIG-9\n' > "$WORK/root/etc/hosts"
echo "0123456789abcdef0123456789abcdef" > "$WORK/root/etc/machine-id"
dd if=/dev/urandom of="$WORK/root/data/blob" bs=1m count=24 2>/dev/null
BLOB="$(shasum "$WORK/root/data/blob" | awk '{ print $1 }')"
dd if=/dev/null of="$WORK/root.img" bs=512 seek="$P2_SIZE" 2>/dev/null
"$E2/mke2fs" -q -t ext4 -b 4096 -L rootfs -d "$WORK/root" "$WORK/root.img"
dd if="$WORK/root.img" of="$CARD" bs=1m seek=$((P2_START / 2048)) conv=notrunc 2>/dev/null
rm "$WORK/root.img"

DEV="$(attach "$CARD")"
DISK="${DEV#/dev/}"
diskutil eraseVolume "MS-DOS FAT32" BOOTFS "${DISK}s1" >/dev/null
mkdir "$WORK/mnt"
diskutil unmount "${DISK}s1" >/dev/null 2>&1
diskutil mount nobrowse -mountPoint "$WORK/mnt" "${DISK}s1" >/dev/null
echo "console=tty1 root=PARTUUID=0-02 rootwait" > "$WORK/mnt/cmdline.txt"
printf '#cloud-config\nhostname: PR-TEST-RIG-9\nusers:\n- name: pi\n  shell: /bin/bash\nssh_pwauth: true\n' > "$WORK/mnt/user-data.orig"
{ cat "$WORK/mnt/user-data.orig"; printf 'runcmd:\n%s\n' "$HOOK"; } > "$WORK/mnt/user-data"
printf 'dsmode: local\ninstance_id: rpios-image\n' > "$WORK/mnt/meta-data"
echo "2026-11-26 15:00:00 Attempt 1 of 3: installing (about 20 minutes)." > "$WORK/mnt/rig-install-status.txt"
diskutil unmount "${DISK}s1" >/dev/null

export RIG_CLONE_ALLOW_IMAGE=1 RIG_CLONE_HEADROOM_MB=16
check "guard: disk image refused without the test switch" "! RIG_CLONE_ALLOW_IMAGE=0 bash '$CLONE' save --disk '$DISK' --image '$IMG' 2>&1 | grep -qv 'disk image'"
check "guard: internal disk refused" "bash '$CLONE' save --disk disk0 --image '$IMG' 2>&1 | grep -Eq 'not an SD card|internal disk|Mac volume|too big'"
check "guard: partition name refused" "bash '$CLONE' save --disk '${DISK}s1' --image '$IMG' 2>&1 | grep -q 'whole disk'"
check "guard: nothing saved yet" "[ ! -e '$IMG' ]"

check "save: refuses a card whose install never finished" "bash '$CLONE' save --disk '$DISK' --image '$IMG' 2>&1 | grep -q 'never finished'"
diskutil unmount "${DISK}s1" >/dev/null 2>&1
diskutil mount nobrowse -mountPoint "$WORK/mnt" "${DISK}s1" >/dev/null
echo "2026-11-26 15:25:00 DONE. Rebooting. Plug in a printer after one minute." >> "$WORK/mnt/rig-install-status.txt"
diskutil unmount "${DISK}s1" >/dev/null
CARD_SUM="$(shasum "$CARD" | awk '{ print $1 }')"
check "save: exits 0" "bash '$CLONE' save --disk '$DISK' --image '$IMG' > '$WORK/save.log' 2>&1"
DEV=""
check "save: source card not changed" "[ \"\$(shasum '$CARD' | awk '{ print \$1 }')\" = '$CARD_SUM' ]"
check "save: image is private" "[ \"\$(stat -f %Lp '$IMG')\" = 600 ]"
check "save: image is smaller than the card" "[ \"\$(stat -f %z '$IMG')\" -lt \$(($CARD_MB * 1048576 / 2)) ]"
check "save: partition table matches the image size" "[ \$((($P2_START + \$(od -An -tu4 -j474 -N4 '$IMG' | tr -d ' ')) * 512)) = \"\$(stat -f %z '$IMG')\" ]"
check "save: filesystem is clean" "'$E2/e2fsck' -fn '$IMG?offset=$OFF' >/dev/null 2>&1"
check "save: hostname kept" "[ \"\$(rootcat '$IMG' /etc/hostname)\" = PR-TEST-RIG-9 ]"
check "save: data survived the shrink" "[ \"\$(blobsum '$IMG')\" = '$BLOB' ]"
check "save: info names the station" "bash '$CLONE' info --image '$IMG' | grep -q 'PR-TEST-RIG-9'"
check "save: refuses to overwrite an image" "bash '$CLONE' save --disk disk0 --image '$IMG' 2>&1 | grep -q 'already an image'"

IMG_SUM="$(shasum "$IMG" | awk '{ print $1 }')"
OUT="$WORK/out.img"
export RIG_CLONE_TARGET_FILE="$OUT"
check "write: refuses no hostname" "! bash '$CLONE' write --image '$IMG' >/dev/null 2>&1"
check "write: refuses a bad hostname" "bash '$CLONE' write 'bad_name' --image '$IMG' 2>&1 | grep -q 'not a valid hostname'"
check "write: refuses the source's own name" "bash '$CLONE' write pr-test-rig-9 --image '$IMG' 2>&1 | grep -q \"can't share a name\""
check "write: nothing written yet" "[ ! -e '$OUT' ]"
check "write: exits 0" "bash '$CLONE' write pr-test-rig-10 --image '$IMG' > '$WORK/write.log' 2>&1"
check "write: saved image not changed" "[ \"\$(shasum '$IMG' | awk '{ print \$1 }')\" = '$IMG_SUM' ]"
check "write: no work files left behind" "[ -z \"\$(find '$WORK/store' -name '.work.*')\" ]"
check "write: hostname set" "[ \"\$(rootcat '$OUT' /etc/hostname)\" = pr-test-rig-10 ]"
check "write: hosts has the new name" "rootcat '$OUT' /etc/hosts | grep -q '^127.0.1.1[[:space:]]*pr-test-rig-10\$'"
check "write: hosts lost the old name" "! rootcat '$OUT' /etc/hosts | grep -qi 'rig-9'"
check "write: hosts kept localhost" "rootcat '$OUT' /etc/hosts | grep -q '^127.0.0.1[[:space:]]*localhost\$'"
check "write: machine ID emptied" "[ -z \"\$(rootcat '$OUT' /etc/machine-id)\" ] && '$E2/debugfs' -R 'stat /etc/machine-id' '$OUT?offset=$OFF' 2>/dev/null | grep -q 'Mode:  0444'"
check "write: files owned by root" "'$E2/debugfs' -R 'stat /etc/hostname' '$OUT?offset=$OFF' 2>/dev/null | grep -q 'User:     0   Group:     0'"
check "write: filesystem is clean" "'$E2/e2fsck' -fn '$OUT?offset=$OFF' >/dev/null 2>&1"
check "write: data intact" "[ \"\$(blobsum '$OUT')\" = '$BLOB' ]"

DEV="$(attach "$OUT")"
diskutil mount nobrowse -mountPoint "$WORK/mnt" "${DEV#/dev/}s1" >/dev/null
check "write: cloud-init hostname set" "grep -qx 'hostname: pr-test-rig-10' '$WORK/mnt/user-data'"
check "write: first line still #cloud-config" "[ \"\$(head -n 1 '$WORK/mnt/user-data')\" = '#cloud-config' ]"
check "write: install hook removed" "! grep -q 'firstBootInstall\\|runcmd' '$WORK/mnt/user-data' && [ ! -e '$WORK/mnt/user-data.orig' ]"
check "write: user kept" "grep -q 'name: pi' '$WORK/mnt/user-data'"
check "write: new instance ID" "grep -Eq '^instance_id: rig-pr-test-rig-10-[0-9]{14}\$' '$WORK/mnt/meta-data' && grep -qx 'dsmode: local' '$WORK/mnt/meta-data'"
check "write: status file says it is a clone" "grep -q 'Cloned from PR-TEST-RIG-9 as pr-test-rig-10' '$WORK/mnt/rig-install-status.txt'"
check "write: no AppleDouble files" "[ -z \"\$(find '$WORK/mnt' -name '._*')\" ]"
diskutil unmount "${DEV#/dev/}s1" >/dev/null
hdiutil detach "$DEV" >/dev/null
DEV=""

check "forget: refuses without a yes" "! bash '$CLONE' forget --image '$IMG' </dev/null >/dev/null 2>&1 && [ -e '$IMG' ]"
check "forget: deletes the image" "bash '$CLONE' forget --yes --image '$IMG' >/dev/null 2>&1 && [ ! -e '$IMG' ] && [ ! -e '$IMG.info' ]"

echo ""
echo "$PASS passed, $FAIL failed"
if [ "$FAIL" != 0 ]; then
    echo "--- save log"; cat "$WORK/save.log" 2>/dev/null
    echo "--- write log"; cat "$WORK/write.log" 2>/dev/null
fi
[ "$FAIL" = 0 ]
