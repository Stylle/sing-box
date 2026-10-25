#!/bin/bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

export is_core_dir="$test_dir/etc/sing-box"
export PORT_HOPPING_TEST_CAPTURE="$test_dir/nft-rules.txt"
mkdir -p "$test_dir/bin"

printf '%s\n' \
    '#!/bin/sh' \
    'if [ "$1" = "-f" ]; then cp "$2" "$PORT_HOPPING_TEST_CAPTURE"; exit 0; fi' \
    'exit 1' >"$test_dir/bin/nft"
chmod +x "$test_dir/bin/nft"
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

port_hopping_remove hysteria2-443.json
[[ ! -f "$is_port_hopping_dir/hysteria2-443.json.conf" ]]

echo 'port-hopping tests passed'
