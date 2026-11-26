#!/bin/bash
# Tests for prep-sd-card.sh against fake boot partitions. Needs no SD card.
#   bash tests/prep-sd-card.test.sh

set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PREP="$REPO/prep-sd-card.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PASS=0
FAIL=0
HOOK="- [ bash, /boot/firmware/printer-test-rig/firstBootInstall.sh, arm ]"

ok() { PASS=$((PASS + 1)); echo "ok    $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL  $1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# make_card <name> <extra user-data lines>
make_card() {
    local card="$WORK/$1"
    mkdir -p "$card"
    echo "console=tty1 root=PARTUUID=0-02 rootwait" > "$card/cmdline.txt"
    printf '#cloud-config\nhostname: PR-TEST-RIG-9\npackages:\n- avahi-daemon\nusers:\n- name: pi\n  shell: /bin/bash\nssh_pwauth: true\n%s' "$2" > "$card/user-data"
    echo "$card"
}

yaml_runcmd() {
    ruby -ryaml -e 'puts YAML.load_file(ARGV[0])["runcmd"].map(&:to_s)' "$1/user-data"
}

card="$(make_card plain "")"
check "plain card: exits 0" "bash '$PREP' '$card' >/dev/null 2>&1"
check "plain card: hook appended" "grep -qF -- '$HOOK' '$card/user-data'"
check "plain card: first line still #cloud-config" "[ \"\$(head -n 1 '$card/user-data')\" = '#cloud-config' ]"
check "plain card: original backed up" "[ -f '$card/user-data.orig' ] && ! grep -q firstBootInstall '$card/user-data.orig'"
check "plain card: setup.sh staged" "git -C '$REPO' show HEAD:setup.sh | cmp -s - '$card/printer-test-rig/setup.sh'"
check "plain card: installer staged" "git -C '$REPO' show HEAD:firstBootInstall.sh | cmp -s - '$card/printer-test-rig/firstBootInstall.sh'"
check "plain card: bundle clones as main at HEAD" "git clone -q -b main '$card/printer-test-rig/printer-test-rig.bundle' '$WORK/clone' 2>/dev/null && [ \"\$(git -C '$WORK/clone' rev-parse HEAD)\" = \"\$(git -C '$REPO' rev-parse HEAD)\" ] && [ \"\$(git -C '$WORK/clone' rev-parse --abbrev-ref HEAD)\" = main ]"
check "plain card: repo left with no stray remote or branch" "[ -z \"\$(git -C '$REPO' remote | grep -v '^origin\$')\" ]"
check "plain card: no AppleDouble files" "[ -z \"\$(find '$card' -name '._*')\" ]"
check "plain card: yaml has one runcmd entry" "[ \"\$(yaml_runcmd '$card' | wc -l | tr -d ' ')\" = 1 ]"

before="$(shasum "$card/user-data")"
check "second run: exits 0" "bash '$PREP' '$card' >/dev/null 2>&1"
check "second run: user-data unchanged" "[ \"\$(shasum '$card/user-data')\" = '$before' ]"

card="$(make_card nonewline "timezone: America/New_York")"
check "no trailing newline: exits 0" "bash '$PREP' '$card' >/dev/null 2>&1"
check "no trailing newline: timezone line intact" "grep -qx 'timezone: America/New_York' '$card/user-data'"
check "no trailing newline: yaml has the hook" "yaml_runcmd '$card' | grep -q firstBootInstall"

card="$(make_card runcmd "$(printf 'runcmd:\n- [ echo, first ]\n- [ echo, second ]\ntimezone: UTC\n')")"
check "existing runcmd: exits 0" "bash '$PREP' '$card' >/dev/null 2>&1"
check "existing runcmd: all three entries" "[ \"\$(yaml_runcmd '$card' | wc -l | tr -d ' ')\" = 3 ]"
check "existing runcmd: key after it survives" "ruby -ryaml -e 'exit(YAML.load_file(ARGV[0])[\"timezone\"] == \"UTC\" ? 0 : 1)' '$card/user-data'"

card="$(make_card indented "$(printf 'runcmd:\n  - [ echo, first ]\n')")"
check "indented runcmd: exits 0" "bash '$PREP' '$card' >/dev/null 2>&1"
check "indented runcmd: both entries" "[ \"\$(yaml_runcmd '$card' | wc -l | tr -d ' ')\" = 2 ]"

card="$(make_card flow "$(printf 'runcmd: [ [ echo, first ] ]\n')")"
before="$(shasum "$card/user-data")"
check "one line runcmd: refuses" "! bash '$PREP' '$card' >/dev/null 2>&1"
check "one line runcmd: user-data untouched" "[ \"\$(shasum '$card/user-data')\" = '$before' ]"
check "one line runcmd: nothing staged" "[ ! -e '$card/printer-test-rig' ] && [ ! -e '$card/user-data.orig' ]"

card="$(make_card notpi "")"
sed -i '' 's/name: pi/name: aaron/' "$card/user-data"
check "wrong username: refuses" "! bash '$PREP' '$card' >/dev/null 2>&1"
check "wrong username: nothing staged" "[ ! -e '$card/printer-test-rig' ]"

card="$(make_card nouserdata "")"
rm "$card/user-data"
check "no user-data: refuses" "! bash '$PREP' '$card' >/dev/null 2>&1"

mkdir -p "$WORK/notacard"
check "not a boot partition: refuses" "! bash '$PREP' '$WORK/notacard' >/dev/null 2>&1"
check "missing folder: refuses" "! bash '$PREP' '$WORK/nope' >/dev/null 2>&1"

echo ""
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
