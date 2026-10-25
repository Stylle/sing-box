#!/bin/bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

export is_core_dir="$test_dir/etc/sing-box"
export PORT_HOPPING_TEST_CAPTURE="$test_dir/nft-rules.txt"
export PORT_HOPPING_TEST_UFW_STATE="$test_dir/ufw-state.txt"
mkdir -p "$test_dir/bin"

printf '%s\n' \
    '#!/bin/sh' \
    'if [ "$1" = "-f" ]; then cp "$2" "$PORT_HOPPING_TEST_CAPTURE"; exit 0; fi' \
    'exit 1' >"$test_dir/bin/nft"
chmod +x "$test_dir/bin/nft"
printf '%s\n' \
    '#!/bin/sh' \
    'state=$PORT_HOPPING_TEST_UFW_STATE' \
    'touch "$state"' \
    'case "$1" in' \
    '  show) cat "$state" ;;' \
    '  allow) printf "ufw allow %s comment '\''%s'\''\n" "$2" "$4" >>"$state" ;;' \
    '  status) echo "Status: active"; cat "$state" ;;' \
    '  --force)' \
    '    target="ufw allow $4 comment '\''$6'\''"' \
    '    grep -Fvx "$target" "$state" >"$state.tmp" || true' \
    '    mv -f "$state.tmp" "$state"' \
    '    ;;' \
    '  *) exit 1 ;;' \
    'esac' >"$test_dir/bin/ufw"
chmod +x "$test_dir/bin/ufw"
PATH="$test_dir/bin:$PATH"

# shellcheck source=../src/port-hopping.sh
. "$repo_dir/src/port-hopping.sh"

[[ $(port_hopping_validate 20000-30000) == '20000-30000' ]]
[[ $(port_hopping_validate 20000:30000) == '20000-30000' ]]
! port_hopping_validate 30000-20000 &>/dev/null
! port_hopping_validate 0-20000 &>/dev/null
! port_hopping_validate 20000-65536 &>/dev/null

port_hopping_save hysteria2-443.json 443 20000-30000
port_hopping_load hysteria2-443.json
[[ $is_hop_target_port == '443' ]]
[[ $is_hop_range == '20000-30000' ]]

port_hopping_apply_all
grep -Fq 'udp dport 20000-30000 redirect to :443' "$PORT_HOPPING_TEST_CAPTURE"

# UFW integration owns only tagged rules and preserves unrelated user rules.
echo "ufw allow 22/tcp comment 'manual'" >"$PORT_HOPPING_TEST_UFW_STATE"
port_hopping_ufw_open >/dev/null
grep -Fq "ufw allow 20000:30000/udp comment 'sing-box-hy2:hysteria2-443.json:range'" "$PORT_HOPPING_TEST_UFW_STATE"
grep -Fq "ufw allow 443/udp comment 'sing-box-hy2:hysteria2-443.json:listen'" "$PORT_HOPPING_TEST_UFW_STATE"
[[ -f $(port_hopping_ufw_marker_file) ]]
port_hopping_ufw_open >/dev/null
[[ $(grep -Fc '20000:30000/udp' "$PORT_HOPPING_TEST_UFW_STATE") == '1' ]]
[[ $(grep -Fc '443/udp' "$PORT_HOPPING_TEST_UFW_STATE") == '1' ]]
port_hopping_ufw_close >/dev/null
grep -Fq "ufw allow 22/tcp comment 'manual'" "$PORT_HOPPING_TEST_UFW_STATE"
! grep -Fq 'sing-box-hy2:' "$PORT_HOPPING_TEST_UFW_STATE"
[[ ! -f $(port_hopping_ufw_marker_file) ]]

# Removing the final hopping config also removes owned UFW rules and disables sync.
port_hopping_ufw_open >/dev/null
port_hopping_remove hysteria2-443.json
port_hopping_ufw_sync >/dev/null
! grep -Fq 'sing-box-hy2:' "$PORT_HOPPING_TEST_UFW_STATE"
[[ ! -f $(port_hopping_ufw_marker_file) ]]

# Verify that displayed/shareable HY2 URIs use the standard multi-port form.
. "$repo_dir/src/core.sh"
openssl() { echo 'sha256 Fingerprint=AA:BB'; }
is_protocol=hysteria2
net=hysteria2
is_addr=example.com
port=443
password=test-password
is_hop_range=20000-30000
is_dont_show_info=1
info
[[ $is_url == hysteria2://test-password@example.com:20000-30000* ]]

[[ ! -f "$is_port_hopping_dir/hysteria2-443.json.conf" ]]

echo 'port-hopping tests passed'
