#!/bin/bash
# Copy an installed station SD card onto more cards, each with its own hostname.
#
#   ./clone-sd-card.sh save                  installed card in the reader -> image on this Mac
#   ./clone-sd-card.sh write pr-test-rig-6   image -> the card in the reader, renamed
#   ./clone-sd-card.sh info                  show what the saved image is
#   ./clone-sd-card.sh forget                delete the saved image
#
#   --disk disk4     pick the card by hand (needed for USB card readers)
#   --image FILE     use another image file (default ~/.printer-test-rig/station.img)
#   --replace        save: overwrite the image that is already there
#   --yes            write, forget: don't ask before erasing
#   --no-verify      write: skip reading the card back
#   --force          skip the "install finished" and "same card" checks
#
# Needs e2fsprogs (brew install e2fsprogs) because macOS can't read the Pi's
# Linux partition. Reading and writing a raw card asks for your Mac password.
# The image holds the station's Wi-Fi password, so it stays out of the repo.
# Shut the Pi down (sudo poweroff) before pulling the card you want to save.

set -euo pipefail

IMAGE="$HOME/.printer-test-rig/station.img"
HEADROOM_MB="${RIG_CLONE_HEADROOM_MB:-2048}"
MAX_CARD_BYTES=$((300 * 1000 * 1000 * 1000))
DISK=""
YES=0
FORCE=0
VERIFY=1
REPLACE=0
CMD=""
NEW_NAME=""
SUDO=""
WORK=""
ATTACHED=""
KEEPALIVE=""
KEY_TYPES=""

die() {
    echo "ERROR: $*" >&2
    exit 1
}

usage() {
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
}

cleanup() {
    if [ -n "$KEEPALIVE" ]; then
        kill "$KEEPALIVE" 2>/dev/null || true
        wait "$KEEPALIVE" 2>/dev/null || true
    fi
    [ -z "$ATTACHED" ] || hdiutil detach "$ATTACHED" -force >/dev/null 2>&1 || true
    [ -z "$WORK" ] || rm -rf "$WORK"
}
trap cleanup EXIT

while [ $# -gt 0 ]; do
    case "$1" in
        --disk) [ $# -ge 2 ] || die "--disk needs a name like disk4"; DISK="$2"; shift ;;
        --image) [ $# -ge 2 ] || die "--image needs a file"; IMAGE="$2"; shift ;;
        --yes) YES=1 ;;
        --force) FORCE=1 ;;
        --replace) REPLACE=1 ;;
        --no-verify) VERIFY=0 ;;
        -h|--help) usage; exit 0 ;;
        -*) die "Unknown option: $1" ;;
        *)
            if [ -z "$CMD" ]; then CMD="$1"
            elif [ -z "$NEW_NAME" ]; then NEW_NAME="$1"
            else die "Too many arguments."
            fi
            ;;
    esac
    shift
done

E2=""
for dir in "$(brew --prefix e2fsprogs 2>/dev/null || true)/sbin" /opt/homebrew/opt/e2fsprogs/sbin /usr/local/opt/e2fsprogs/sbin; do
    if [ -x "$dir/debugfs" ]; then
        E2="$dir"
        break
    fi
done

need_e2() {
    [ -n "$E2" ] || die "Needs e2fsprogs. Install it with: brew install e2fsprogs"
}

disk_val() {
    diskutil info -plist "$1" 2>/dev/null | plutil -extract "$2" raw -o - - 2>/dev/null || true
}

# Little endian fields out of a saved partition table. Macs are little endian.
u32() { od -An -tu4 -j "$2" -N4 "$1" | tr -d ' '; }
u8() { od -An -tu1 -j "$2" -N1 "$1" | tr -d ' '; }

# Sets P1_START P1_SIZE P2_START (in 512 byte sectors) from a file
# holding the first sector of a card or image.
parse_mbr() {
    local mbr="$1"
    [ "$(od -An -tx1 -j510 -N2 "$mbr" | tr -d ' ')" = "55aa" ] || die "No partition table found. Is this a Raspberry Pi card?"
    case "$(u8 "$mbr" 450)" in
        11|12|14) ;;
        238) die "This card uses GPT. Only cards written by Raspberry Pi Imager are supported." ;;
        *) die "The first partition is not a Pi boot partition." ;;
    esac
    [ "$(u8 "$mbr" 466)" = 131 ] || die "The second partition is not a Linux partition."
    [ "$(u8 "$mbr" 482)" = 0 ] && [ "$(u8 "$mbr" 498)" = 0 ] || die "This card has more than two partitions."
    P1_START="$(u32 "$mbr" 454)"
    P1_SIZE="$(u32 "$mbr" 458)"
    P2_START="$(u32 "$mbr" 470)"
    [ "$P2_START" -ge $((P1_START + P1_SIZE)) ] || die "The partition table makes no sense."
}

# Refuses anything that is not plainly an SD card. A wrong disk here means
# erasing somebody's drive.
pick_disk() {
    local d proto found="" count=0
    if [ -n "$DISK" ]; then
        DISK="${DISK#/dev/}"
        DISK="${DISK#r}"
        [[ "$DISK" =~ ^disk[0-9]+$ ]] || die "--disk wants a whole disk like disk4, not a partition."
    else
        for d in $(diskutil list -plist | plutil -extract WholeDisks json -o - - | tr -d '[]"' | tr ',' ' '); do
            if [ "$(disk_val "$d" BusProtocol)" = "Secure Digital" ]; then
                found="$found $d"
                count=$((count + 1))
            fi
        done
        [ "$count" -ge 1 ] || die "No SD card found in the built in reader. Put the card in. If something just wrote to it, pull it out and put it back in. For a USB card reader use --disk (see: diskutil list)."
        [ "$count" -eq 1 ] || die "More than one SD card found:$found. Pick one with --disk."
        DISK="${found# }"
    fi

    proto="$(disk_val "$DISK" BusProtocol)"
    DISK_BYTES="$(disk_val "$DISK" TotalSize)"
    [ -n "$DISK_BYTES" ] || die "$DISK does not exist. See: diskutil list"
    case "$proto" in
        "Secure Digital") ;;
        USB) [ "$(disk_val "$DISK" Internal)" = false ] || die "$DISK is an internal disk." ;;
        "Disk Image") [ "${RIG_CLONE_ALLOW_IMAGE:-0}" = 1 ] || die "$DISK is a disk image, not a card." ;;
        *) die "$DISK is not an SD card (it is on $proto)." ;;
    esac
    [ "$DISK_BYTES" -le "$MAX_CARD_BYTES" ] || die "$DISK is $((DISK_BYTES / 1000000000)) GB, too big to be a station card."
    if diskutil list "$DISK" | grep -Eq 'Apple_APFS|Apple_HFS|Apple_CoreStorage|Apple_Boot'; then
        die "$DISK has a Mac volume on it. Not touching it."
    fi
}

# mode r or w. Sets SUDO when the card can't be opened as this user.
get_access() {
    local dev="/dev/r$DISK"
    SUDO=""
    if [ "$1" = r ] && [ -r "$dev" ]; then return; fi
    if [ "$1" = w ] && [ -w "$dev" ]; then return; fi
    SUDO="sudo"
    if ! sudo -n true 2>/dev/null; then
        [ -t 0 ] || die "This needs your Mac password. Run it yourself in Terminal: cd $(cd "$(dirname "$0")" && pwd) && ./$(basename "$0") $ORIG_ARGS"
        echo "Raw access to the card needs your Mac password."
        sudo -v || die "No admin access."
    fi
    # A slow card reader outlasts sudo's five minute memory. Keep it fresh so
    # the password is only asked once.
    ( while kill -0 $$ 2>/dev/null; do sudo -n -v 2>/dev/null || exit; sleep 60; done ) &
    KEEPALIVE=$!
}

fs_stat() {
    "$E2/debugfs" -R stats "$1" 2>/dev/null | awk -F': *' -v key="$2" '$1 == key { print $2; exit }'
}

fs_cat() {
    "$E2/debugfs" -R "cat $2" "$1" 2>/dev/null
}

fsck_ok() {
    local rc=0
    "$E2/e2fsck" "$1" "$2" >/dev/null 2>&1 || rc=$?
    [ "$rc" -le 1 ]
}

# SHA-256 of the first $2 bytes of a card or file. dd reads whole 4 MB blocks
# and head cuts it off, which kills dd with a broken pipe. That is expected, so
# dd's exit status is ignored. A short or failed read still shows as a wrong sum.
sum_of() {
    local blocks=$((($2 + 4194303) / 4194304))
    { $3 dd if="$1" bs=4m count="$blocks" 2>/dev/null || true; } | head -c "$2" | shasum -a 256 | awk '{ print $1 }'
}

set_size() {
    dd if=/dev/null of="$1" bs=1 count=0 seek="$2" 2>/dev/null
}

human() {
    awk -v b="$1" 'BEGIN { printf "%.1f GB", b / 1000000000 }'
}

load_image() {
    [ -f "$IMAGE" ] || die "No saved image at $IMAGE. Put an installed card in and run: ./$(basename "$0") save"
    need_e2
    [ -n "$WORK" ] || WORK="$(mktemp -d)"
    dd if="$IMAGE" of="$WORK/mbr" bs=512 count=1 2>/dev/null
    parse_mbr "$WORK/mbr"
    IMAGE_BYTES="$(stat -f %z "$IMAGE")"
    SRC_NAME="$(fs_cat "$IMAGE?offset=$((P2_START * 512))" /etc/hostname | tr -d '[:space:]')"
    [ -n "$SRC_NAME" ] || die "$IMAGE is damaged (no hostname inside). Save the card again."
}

cmd_save() {
    local dev head_bytes tmp root fs bs cur free need avail min target mount status root_bytes
    need_e2
    [ ! -e "$IMAGE" ] || [ "$REPLACE" = 1 ] || die "There is already an image at $IMAGE (see: ./$(basename "$0") info). Add --replace to overwrite it."
    pick_disk
    dev="/dev/r$DISK"

    # Read only, so saving never changes the card being copied.
    diskutil mount readOnly "${DISK}s1" >/dev/null 2>&1 || true
    mount="$(disk_val "${DISK}s1" MountPoint)"
    status="$mount/rig-install-status.txt"
    if [ -n "$mount" ] && [ -f "$status" ]; then
        if ! grep -q 'DONE' "$status" && [ "$FORCE" = 0 ]; then
            die "The install on this card never finished. Last line of its status file: $(tail -n 1 "$status"). Use --force to copy it anyway."
        fi
    elif [ "$FORCE" = 0 ]; then
        echo "NOTE: no install status file on this card, so I can't tell if the install finished."
    fi

    get_access r
    diskutil unmountDisk "$DISK" >/dev/null || die "Could not unmount $DISK. Close anything using the card."
    WORK="$(mktemp -d)"
    # Redirect instead of of=, so the file belongs to this user and not root.
    $SUDO dd if="$dev" bs=512 count=1 2>/dev/null > "$WORK/mbr" || die "Could not read $DISK."
    parse_mbr "$WORK/mbr"
    head_bytes=$((P2_START * 512))

    mkdir -p "$(dirname "$IMAGE")"
    chmod 700 "$(dirname "$IMAGE")" 2>/dev/null || true
    umask 077
    tmp="$IMAGE.part"
    root="$IMAGE.root.part"
    rm -f "$tmp" "$root"
    fs="$tmp?offset=$head_bytes"

    # The copy is made twice on the way (raw, then packed), so check for room.
    bs="$($SUDO "$E2/debugfs" -R stats "${dev}s2" 2>/dev/null | awk -F': *' '$1 == "Block size" { print $2; exit }')"
    cur="$($SUDO "$E2/debugfs" -R stats "${dev}s2" 2>/dev/null | awk -F': *' '$1 == "Block count" { print $2; exit }')"
    free="$($SUDO "$E2/debugfs" -R stats "${dev}s2" 2>/dev/null | awk -F': *' '$1 == "Free blocks" { print $2; exit }')"
    [ -n "$bs" ] && [ -n "$cur" ] && [ -n "$free" ] || die "Could not read the Linux partition on $DISK."
    need=$(((cur - free) * bs * 2 + head_bytes + HEADROOM_MB * 1048576))
    avail=$(($(df -k "$(dirname "$IMAGE")" | awk 'NR == 2 { print $4 }') * 1024))
    [ "$avail" -ge "$need" ] || die "Not enough free space on this Mac. Needs $(human "$need"), has $(human "$avail")."

    echo "=== Reading the boot partition from $DISK ($(human "$DISK_BYTES")) ==="
    $SUDO dd if="$dev" bs=1m count=$(((head_bytes + 1048575) / 1048576)) 2>/dev/null > "$tmp" || die "Could not read $DISK."
    set_size "$tmp" "$head_bytes"

    echo "=== Reading the Linux partition ($(human $(((cur - free) * bs))) in use, a few minutes) ==="
    $SUDO "$E2/e2image" -ra "${dev}s2" "$root" >/dev/null 2>&1 \
        || die "Could not read the Linux partition. If the Pi was unplugged without a shutdown, boot it, run sudo poweroff, and try again."
    [ -z "$SUDO" ] || $SUDO chown "$(id -u):$(id -g)" "$root"

    echo "=== Checking and shrinking the copy ==="
    fsck_ok -fy "$root" || die "The copy has filesystem errors that could not be fixed."
    min="$("$E2/resize2fs" -P "$root" 2>/dev/null | awk -F': *' '/minimum size/ { print $2 }')"
    [ -n "$min" ] || die "Could not work out how far the copy can shrink."
    target=$((min + HEADROOM_MB * 1048576 / bs))
    if [ "$target" -lt "$cur" ]; then
        "$E2/resize2fs" "$root" "$target" >/dev/null 2>&1 || die "Could not shrink the copy."
    else
        target="$cur"
    fi
    fsck_ok -fn "$root" || die "The shrunk copy failed its check."
    # Pack it behind the boot partition. Only used blocks are written.
    "$E2/e2image" -ra -O "$head_bytes" "$root" "$tmp" >/dev/null 2>&1 || die "Could not build the image."
    rm -f "$root"
    root_bytes=$((target * bs))
    set_size "$tmp" $((head_bytes + root_bytes))

    # Partition 2's sector count, 4 bytes little endian at offset 474.
    local sectors=$((root_bytes / 512))
    # shellcheck disable=SC2059
    printf "$(printf '\\x%02x\\x%02x\\x%02x\\x%02x' $((sectors & 255)) $(((sectors >> 8) & 255)) $(((sectors >> 16) & 255)) $(((sectors >> 24) & 255)))" \
        | dd of="$tmp" bs=1 seek=474 conv=notrunc 2>/dev/null
    fsck_ok -fn "$fs" || die "The shrunk copy failed its check."

    mv "$tmp" "$IMAGE"
    chmod 600 "$IMAGE"
    load_image
    {
        echo "hostname: $SRC_NAME"
        echo "saved: $(date '+%Y-%m-%d %H:%M')"
        echo "from: $DISK ($(human "$DISK_BYTES"))"
    } > "$IMAGE.info"
    diskutil eject "$DISK" >/dev/null 2>&1 || true

    echo ""
    echo "=== Saved $SRC_NAME ==="
    echo "Image: $IMAGE ($(human "$IMAGE_BYTES"), fits any card that size or bigger)"
    echo "Card ejected. Put a blank card in and run: ./$(basename "$0") write <new-hostname>"
}

# Queues "replace this file inside the image" for debugfs. Keeps the mode the
# file had, or uses $4 when it is new. Files written by debugfs belong to root.
put_file() {
    local fs="$1" src="$2" path="$3" mode
    mode="$("$E2/debugfs" -R "stat $path" "$fs" 2>/dev/null | sed -n 's/.*Mode:  \([0-7]*\).*/\1/p' | head -n 1)"
    [ -n "$mode" ] || mode="$4"
    printf 'rm %s\nwrite %s %s\nsif %s mode 010%s\n' "$path" "$src" "$path" "$path" "$mode" >> "$WORK/root/cmds"
}

# Everything that makes the copy its own machine, inside the Linux partition:
# hostname, hosts, machine ID, cloud-init's record of the hostname, and SSH
# host keys. Pi OS only makes host keys on a first boot, so they are made here.
rename_root() {
    local fs="$1" t="$WORK/root" type types
    mkdir -p "$t"
    chmod 700 "$t"
    : > "$t/cmds"

    printf '%s\n' "$NEW_NAME" > "$t/hostname"
    fs_cat "$fs" /etc/hosts | awk -v old="$SRC_NAME" -v new="$NEW_NAME" '
        { for (i = 2; i <= NF; i++) if (tolower($i) == tolower(old)) $i = new; print }
    ' > "$t/hosts"
    grep -q . "$t/hosts" || printf '127.0.0.1\tlocalhost\n' > "$t/hosts"
    grep -qiw "$NEW_NAME" "$t/hosts" || printf '127.0.1.1\t%s\n' "$NEW_NAME" >> "$t/hosts"
    # An empty machine-id makes systemd create a fresh one on the next boot.
    : > "$t/machine-id"
    put_file "$fs" hostname /etc/hostname 0644
    put_file "$fs" hosts /etc/hosts 0644
    put_file "$fs" machine-id /etc/machine-id 0444

    # Without these cloud-init still thinks the old name is the one it set.
    if [ -n "$(fs_cat "$fs" /var/lib/cloud/data/previous-hostname)" ]; then
        printf '%s\n' "$NEW_NAME" > "$t/previous-hostname"
        put_file "$fs" previous-hostname /var/lib/cloud/data/previous-hostname 0644
    fi
    if [ -n "$(fs_cat "$fs" /var/lib/cloud/data/set-hostname)" ]; then
        printf '{\n "fqdn": "%s",\n "hostname": "%s"\n}\n' "$NEW_NAME" "$NEW_NAME" > "$t/set-hostname"
        put_file "$fs" set-hostname /var/lib/cloud/data/set-hostname 0644
    fi

    types="$("$E2/debugfs" -R "ls -p /etc/ssh" "$fs" 2>/dev/null | awk -F/ '{ print $6 }' | sed -n 's/^ssh_host_\([a-z0-9]*\)_key$/\1/p')"
    [ -n "$types" ] || die "No SSH host keys found inside the image."
    for type in $types; do
        fs_cat "$fs" "/etc/ssh/ssh_host_${type}_key.pub" > "$t/old_$type.pub"
        ssh-keygen -q -t "$type" -N '' -C "root@$NEW_NAME" -f "$t/ssh_host_${type}_key" \
            || die "Could not make a new $type SSH host key."
        put_file "$fs" "ssh_host_${type}_key" "/etc/ssh/ssh_host_${type}_key" 0600
        put_file "$fs" "ssh_host_${type}_key.pub" "/etc/ssh/ssh_host_${type}_key.pub" 0644
    done

    (cd "$t" && "$E2/debugfs" -w -f cmds "$fs" >/dev/null 2>&1) || true

    [ "$(fs_cat "$fs" /etc/hostname)" = "$NEW_NAME" ] || die "Could not set the hostname inside the image."
    fs_cat "$fs" /etc/hosts | cmp -s - "$t/hosts" || die "Could not update /etc/hosts inside the image."
    [ -z "$(fs_cat "$fs" /etc/machine-id)" ] || die "Could not reset the machine ID inside the image."
    for type in $types; do
        if ! fs_cat "$fs" "/etc/ssh/ssh_host_${type}_key" | cmp -s - "$t/ssh_host_${type}_key" \
            || ! fs_cat "$fs" "/etc/ssh/ssh_host_${type}_key.pub" | cmp -s - "$t/ssh_host_${type}_key.pub"; then
            die "Could not write the new $type SSH host key into the image."
        fi
        ! cmp -s "$t/old_$type.pub" "$t/ssh_host_${type}_key.pub" || die "The $type SSH host key did not change."
        "$E2/debugfs" -R "stat /etc/ssh/ssh_host_${type}_key" "$fs" 2>/dev/null | grep -q 'Mode:  0600' \
            || die "The new $type SSH host key has the wrong permissions."
    done
    # The private keys only belong on the card.
    rm -f "$t"/ssh_host_*_key
    fsck_ok -fn "$fs" || die "The image failed its check after the rename."
    KEY_TYPES="$(echo "$types" | tr '\n' ' ')"
}

# Boot partition: cloud-init reads user-data on every boot and writes the
# hostname from it into /etc/hosts, so the name has to change there too.
rename_boot() {
    local img="$1" boot="$WORK/boot" out dev
    mkdir -p "$boot"
    out="$(hdiutil attach -imagekey diskimage-class=CRawDiskImage -nomount "$img")" || die "Could not open the image."
    dev="$(echo "$out" | awk 'NR == 1 { print $1 }')"
    ATTACHED="$dev"
    diskutil mount nobrowse -mountPoint "$boot" "${dev}s1" >/dev/null || die "Could not mount the image's boot partition."

    if [ -f "$boot/user-data" ]; then
        # Drop the first boot install hook. The program is already installed.
        if [ -f "$boot/user-data.orig" ] && ! grep -q 'firstBootInstall.sh' "$boot/user-data.orig"; then
            cp "$boot/user-data.orig" "$WORK/user-data"
        else
            awk '
                /firstBootInstall\.sh/ { next }
                held != "" { if ($0 ~ /^[[:space:]]*-/) print held; held = "" }
                /^runcmd:[[:space:]]*$/ { held = $0; next }
                { print }
            ' "$boot/user-data" > "$WORK/user-data"
        fi
        if grep -q '^hostname:' "$WORK/user-data"; then
            sed -i '' "s/^hostname:.*/hostname: $NEW_NAME/" "$WORK/user-data"
        else
            printf 'hostname: %s\n' "$NEW_NAME" >> "$WORK/user-data"
        fi
        head -n 1 "$WORK/user-data" | grep -q '^#cloud-config' || die "user-data lost its #cloud-config first line."
        if command -v ruby >/dev/null 2>&1; then
            ruby -ryaml -e 'd = YAML.load_file(ARGV[0]); exit(d.is_a?(Hash) && d["hostname"] == ARGV[1] ? 0 : 1)' "$WORK/user-data" "$NEW_NAME" \
                || die "user-data is not valid YAML after the rename."
        fi
        cp "$WORK/user-data" "$boot/user-data"
        rm -f "$boot/user-data.orig"
    else
        echo "NOTE: no cloud-init user-data on the card. Hostname is set in the Linux partition only."
    fi
    if [ -f "$boot/rig-install-status.txt" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') Cloned from $SRC_NAME as $NEW_NAME." >> "$boot/rig-install-status.txt"
    fi
    find "$boot" -name '._*' -delete 2>/dev/null || true

    sync
    diskutil unmount "${dev}s1" >/dev/null || die "Could not unmount the image's boot partition."
    hdiutil detach "$dev" >/dev/null || die "Could not close the image."
    ATTACHED=""
}

cmd_write() {
    local target dev mount answer work fs card_name want got
    [ -n "$NEW_NAME" ] || die "Give the new hostname: ./$(basename "$0") write pr-test-rig-6"
    [[ "$NEW_NAME" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]] || die "\"$NEW_NAME\" is not a valid hostname. Letters, numbers and dashes only."
    load_image
    [ "$(echo "$NEW_NAME" | tr '[:upper:]' '[:lower:]')" != "$(echo "$SRC_NAME" | tr '[:upper:]' '[:lower:]')" ] \
        || die "$NEW_NAME is the name of the station the image came from. Two stations can't share a name."

    target="${RIG_CLONE_TARGET_FILE:-}"
    if [ -z "$target" ]; then
        pick_disk
        dev="/dev/r$DISK"
        [ "$DISK_BYTES" -ge "$IMAGE_BYTES" ] || die "The card is $(human "$DISK_BYTES") and the image needs $(human "$IMAGE_BYTES")."

        diskutil mount readOnly "${DISK}s1" >/dev/null 2>&1 || true
        mount="$(disk_val "${DISK}s1" MountPoint)"
        if [ -n "$mount" ] && [ -f "$mount/user-data" ] && [ "$FORCE" = 0 ]; then
            card_name="$(sed -n 's/^hostname:[[:space:]]*//p' "$mount/user-data" | head -n 1)"
            [ "$(echo "$card_name" | tr '[:upper:]' '[:lower:]')" != "$(echo "$SRC_NAME" | tr '[:upper:]' '[:lower:]')" ] \
                || die "The card in the reader is $SRC_NAME, the one the image came from. Swap in the blank card."
        fi

        echo "About to erase this card and make it $NEW_NAME:"
        diskutil list "$DISK" | sed 's/^/    /'
        if [ "$YES" = 0 ]; then
            [ -t 0 ] || die "Not erasing without a yes. Add --yes."
            printf 'Type %s to erase it: ' "$DISK"
            read -r answer
            [ "$answer" = "$DISK" ] || die "Stopped, nothing was erased."
        fi
        get_access w
    fi

    echo "=== Renaming a copy of the image to $NEW_NAME ==="
    work="$(dirname "$IMAGE")/.work.$$.img"
    cp -c "$IMAGE" "$work" 2>/dev/null || cp "$IMAGE" "$work"
    # shellcheck disable=SC2064
    trap "rm -f '$work'; cleanup" EXIT
    fs="$work?offset=$((P2_START * 512))"
    rename_root "$fs"
    rename_boot "$work"
    want="$(sum_of "$work" "$IMAGE_BYTES" "")"

    if [ -n "$target" ]; then
        cp "$work" "$target"
        if [ "$VERIFY" = 1 ]; then
            [ "$(sum_of "$target" "$IMAGE_BYTES" "")" = "$want" ] || die "The copy does not match what was written."
            echo "Card matches the image."
        fi
    else
        echo "=== Writing $(human "$IMAGE_BYTES") to $DISK (several minutes) ==="
        diskutil unmountDisk "$DISK" >/dev/null || die "Could not unmount $DISK."
        $SUDO dd if="$work" of="$dev" bs=4m 2>/dev/null || die "Writing the card failed. Try again, or try another card."
        sync
        if [ "$VERIFY" = 1 ]; then
            echo "=== Reading the card back to check it ==="
            got="$(sum_of "$dev" "$IMAGE_BYTES" "$SUDO")"
            [ "$got" = "$want" ] || die "The card does not match what was written. The card may be bad, try another one."
            echo "Card matches the image."
        fi
        diskutil eject "$DISK" >/dev/null 2>&1 || true
    fi

    echo ""
    echo "=== Card ready for $NEW_NAME (copy of $SRC_NAME) ==="
    echo "New machine ID on first boot, new SSH host keys: $KEY_TYPES"
    echo "Card ejected. Put it in the Pi and plug in power. No install needed."
    echo "Then: ssh pi@$(echo "$NEW_NAME" | tr '[:upper:]' '[:lower:]').local"
}

cmd_info() {
    load_image
    echo "Image: $IMAGE ($(human "$IMAGE_BYTES"))"
    echo "Station it came from: $SRC_NAME"
    [ ! -f "$IMAGE.info" ] || grep -v '^hostname:' "$IMAGE.info"
}

cmd_forget() {
    local answer
    [ -e "$IMAGE" ] || die "No saved image at $IMAGE."
    if [ "$YES" = 0 ]; then
        [ -t 0 ] || die "Not deleting without a yes. Add --yes."
        printf 'Delete %s? Type yes: ' "$IMAGE"
        read -r answer
        [ "$answer" = yes ] || die "Stopped, nothing was deleted."
    fi
    rm -f "$IMAGE" "$IMAGE.info" "$IMAGE.part" "$IMAGE.root.part"
    echo "Deleted $IMAGE."
}

ORIG_ARGS="$CMD${NEW_NAME:+ $NEW_NAME}"
case "$CMD" in
    save) cmd_save ;;
    write) cmd_write ;;
    info) cmd_info ;;
    forget) cmd_forget ;;
    "") usage; exit 1 ;;
    *) die "Unknown command: $CMD. Try --help." ;;
esac
