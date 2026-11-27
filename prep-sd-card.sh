#!/bin/bash
# Put the Printer Test Rig on a freshly imaged SD card, from a Mac.
#
# Run it after Raspberry Pi Imager has written the card (STATION-GUIDE.md
# section 3). The Pi then installs the program by itself on first boot, so
# section 4 is not needed. macOS can only write the card's boot partition, so
# the program is staged there and firstBootInstall.sh moves it into place.
#
#   ./prep-sd-card.sh                  card mounted at /Volumes/bootfs
#   ./prep-sd-card.sh /Volumes/other   card mounted somewhere else
#   ./prep-sd-card.sh --no-eject       leave the card mounted when done
#
# Stages the commit you have checked out. Imager ejects the card when it
# finishes, so pull it out and put it back in before running this.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOOT="/Volumes/bootfs"
EJECT=1
HOOK="- [ bash, /boot/firmware/printer-test-rig/firstBootInstall.sh, arm ]"

for arg in "$@"; do
    case "$arg" in
        --no-eject) EJECT=0 ;;
        -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "Unknown option: $arg" >&2; exit 1 ;;
        *) BOOT="${arg%/}" ;;
    esac
done

die() {
    echo "ERROR: $*" >&2
    exit 1
}

USER_DATA="$BOOT/user-data"
DEST="$BOOT/printer-test-rig"

[ -d "$BOOT" ] || die "$BOOT not found. Put the card in. If Imager just wrote it, pull it out and put it back in."
[ -f "$BOOT/cmdline.txt" ] || die "$BOOT is not a Raspberry Pi boot partition."
[ -f "$USER_DATA" ] || die "No user-data on the card. Write it again with Raspberry Pi Imager and fill in the OS customisation settings (STATION-GUIDE.md section 3)."
grep -Eq '^[[:space:]]*-?[[:space:]]*name:[[:space:]]*"?pi"?[[:space:]]*$' "$USER_DATA" \
    || die "The card's username is not pi. The program only works with pi. Write the card again."
git -C "$SCRIPT_DIR" cat-file -e HEAD:firstBootInstall.sh 2>/dev/null \
    || die "firstBootInstall.sh is not committed in $SCRIPT_DIR. Run git pull, or commit it."
if ! grep -q 'firstBootInstall.sh' "$USER_DATA" && grep -Eq '^runcmd:[[:space:]]*[^[:space:]#]' "$USER_DATA"; then
    die "user-data has a one line runcmd. Add this to it by hand, then run this again: $HOOK"
fi

COMMIT="$(git -C "$SCRIPT_DIR" rev-parse --short HEAD)"
BRANCH="$(git -C "$SCRIPT_DIR" rev-parse --abbrev-ref HEAD)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ -n "$(git -C "$SCRIPT_DIR" status --porcelain --untracked-files=no)" ]; then
    echo "NOTE: uncommitted changes in $SCRIPT_DIR are not going on the card."
fi
if ! git -C "$SCRIPT_DIR" merge-base --is-ancestor HEAD origin/main 2>/dev/null; then
    echo "NOTE: $COMMIT is not on GitHub main yet. Merge it (no squash) so \"git pull\" on the station keeps working."
fi
HOSTNAME_ON_CARD="$(sed -n 's/^hostname:[[:space:]]*//p' "$USER_DATA" | head -n 1)"

echo "=== Copying the program ($BRANCH @ $COMMIT) to $DEST ==="
rm -rf "$DEST"
mkdir -p "$DEST"
git -C "$SCRIPT_DIR" archive HEAD | COPYFILE_DISABLE=1 tar -x -C "$DEST"
# The station clones this bundle and tracks GitHub main, so the bundle's
# branch has to be called main whatever branch is checked out here.
git init -q --bare "$WORK/bundle.git"
git -C "$SCRIPT_DIR" push -q "$WORK/bundle.git" HEAD:refs/heads/main
git -C "$WORK/bundle.git" bundle create "$DEST/printer-test-rig.bundle" main 2>/dev/null
echo "$BRANCH $COMMIT staged $(date '+%Y-%m-%d %H:%M')" > "$DEST/VERSION"
find "$DEST" -name '._*' -delete

echo "=== Hooking first boot ==="
if grep -q 'firstBootInstall.sh' "$USER_DATA"; then
    echo "Already hooked, leaving user-data alone."
else
    [ -f "$USER_DATA.orig" ] || cp "$USER_DATA" "$USER_DATA.orig"
    if grep -Eq '^runcmd:' "$USER_DATA"; then
        # Join the existing list, matching its indent so the YAML stays valid.
        awk -v hook="$HOOK" '
            /^runcmd:/ && !seen {
                seen = 1
                print
                if ((getline nextline) > 0) {
                    indent = nextline
                    sub(/-.*/, "", indent)
                    if (nextline !~ /^[[:space:]]*-/) indent = ""
                    print indent hook
                    print nextline
                } else {
                    print hook
                }
                next
            }
            { print }
        ' "$USER_DATA.orig" > "$USER_DATA.new"
        mv "$USER_DATA.new" "$USER_DATA"
    else
        [ -z "$(tail -c 1 "$USER_DATA")" ] || echo >> "$USER_DATA"
        printf 'runcmd:\n%s\n' "$HOOK" >> "$USER_DATA"
    fi
    echo "Added the first boot hook to user-data. Original saved as user-data.orig."
fi

echo "=== Checking the card ==="
if command -v ruby >/dev/null 2>&1; then
    ruby -ryaml -e '
        d = YAML.load_file(ARGV[0])
        cmds = d.is_a?(Hash) ? d["runcmd"] : nil
        ok = cmds.is_a?(Array) && cmds.any? { |c| c.to_s.include?("firstBootInstall.sh") }
        exit(ok ? 0 : 1)
    ' "$USER_DATA" || die "user-data is not valid YAML after the edit. Restore it from user-data.orig."
    echo "user-data parses and has the hook."
fi
head -n 1 "$USER_DATA" | grep -q '^#cloud-config' || die "user-data lost its #cloud-config first line."

CHECK="$WORK/check"
mkdir "$CHECK"
git -C "$SCRIPT_DIR" archive HEAD | COPYFILE_DISABLE=1 tar -x -C "$CHECK"
diff -r -x printer-test-rig.bundle -x VERSION "$CHECK" "$DEST" >/dev/null \
    || die "Files on the card do not match the repo. Run this again."
git clone -q -b main "$DEST/printer-test-rig.bundle" "$WORK/clone" 2>/dev/null \
    && [ "$(git -C "$WORK/clone" rev-parse HEAD)" = "$(git -C "$SCRIPT_DIR" rev-parse HEAD)" ] \
    || die "The git bundle on the card is damaged. Run this again."
echo "$(git -C "$SCRIPT_DIR" ls-tree -r --name-only HEAD | wc -l | tr -d ' ') files match the repo, bundle clones to $COMMIT."

sync
if [ "$EJECT" = 1 ] && mount | grep -q " on $BOOT "; then
    diskutil eject "$BOOT" >/dev/null
    echo "Card ejected."
fi

echo ""
echo "=== Card ready${HOSTNAME_ON_CARD:+ for $HOSTNAME_ON_CARD} ==="
echo "Put it in the Pi and plug in power. It needs internet."
echo "It installs by itself in about 25 minutes, then reboots."
echo "After that, plug in a printer and it prints the test page."
