#!/bin/bash
set -eo pipefail
repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
export is_core_dir="$test_dir/etc/sing-box"
is_conf_dir=$is_core_dir/conf
is_config_file=hysteria2-443.json
is_core=sing-box
is_core_name=sing-box
mkdir -p "$is_conf_dir"
. "$repo_dir/src/port-hopping.sh"
. "$repo_dir/src/hy2-obfs.sh"
. "$repo_dir/src/core.sh"
err() { echo "$*" >&2; return 1; }
warn() { echo "$*" >&2; }
_green() { echo "$*"; }
openssl() { if [[ $1 == rand ]]; then echo 1234567890abcdef1234567890abcdef; else echo 'sha256 Fingerprint=AA:BB'; fi; }
is_core_bin=$test_dir/core-check
printf '%s\n' '#!/bin/bash' '[[ ! ${FAIL_CHECK:-} ]]' >"$is_core_bin"
chmod +x "$is_core_bin"
hy2_obfs_restart() {
    [[ ! ${FAIL_RESTART:-} ]] || return 1
    echo restart >>"$test_dir/restarts"
}
jq -n '{inbounds:[{type:"hysteria2",tag:"hy2-test",listen:"::",listen_port:443,users:[{password:"auth-password"}],tls:{enabled:true,certificate_path:"/tls/cert",key_path:"/tls/key"},ignore_client_bandwidth:true}],outbounds:[{type:"direct"}]}' >"$is_conf_dir/$is_config_file"
cp "$is_conf_dir/$is_config_file" "$test_dir/original.json"
port_hopping_save "$is_config_file" 443 20000-30000
cp "$is_port_hopping_dir/$is_config_file.conf" "$test_dir/hopping.conf"

secret='pass // &?#%"\ $() 中文'
hy2_obfs_apply on "$secret"
[[ $(jq -r '.inbounds[0].obfs.password' "$is_conf_dir/$is_config_file") == "$secret" ]]
jq 'del(.inbounds[0].obfs)' "$is_conf_dir/$is_config_file" >"$test_dir/without-obfs.json"
cmp "$test_dir/original.json" "$test_dir/without-obfs.json"
cmp "$test_dir/hopping.conf" "$is_port_hopping_dir/$is_config_file.conf"

# Real loader and regeneration must preserve JSON escapes and URL parameters.
ip=example.com
is_tls_key=/tls/key
is_tls_cer=/tls/cert
is_dont_show_info=1
get info hy2 || true # Upstream get/file uses a final conditional as its status.
[[ $is_hy2_obfs_type == salamander && $is_hy2_obfs_password == "$secret" ]]
info
[[ $is_url == *':20000-30000?'* && $is_url == *'&obfs=salamander&obfs-password='* ]]
encoded=$(jq -rn --arg value "$secret" '$value|@uri')
[[ $is_url == *"obfs-password=$encoded#"* ]]
[[ " ${is_can_change[*]} " == *' 14 '* ]]
[[ $is_url != *"$secret"* ]]
password=new-auth-password
get protocol hysteria2 || true
jq -n "{inbounds:[{type:\"hysteria2\",listen_port:8443,$json_str}]}" >"$test_dir/rebuilt.json"
[[ $(jq -r '.inbounds[0].obfs.password' "$test_dir/rebuilt.json") == "$secret" ]]
[[ $(jq -r '.inbounds[0].users[0].password' "$test_dir/rebuilt.json") == new-auth-password ]]

# Invalid candidate / password must leave bytes and running service unchanged.
cp "$is_conf_dir/$is_config_file" "$test_dir/before.json"
export FAIL_CHECK=1
! hy2_obfs_apply off
unset FAIL_CHECK
cmp "$test_dir/before.json" "$is_conf_dir/$is_config_file"
[[ $(wc -l <"$test_dir/restarts") == 1 ]]
! hy2_obfs_apply on ''
! hy2_obfs_apply on $'bad\nsecret'
cmp "$test_dir/before.json" "$is_conf_dir/$is_config_file"

export FAIL_RESTART=1
! hy2_obfs_apply off
unset FAIL_RESTART
cmp "$test_dir/before.json" "$is_conf_dir/$is_config_file"

hy2_obfs_apply off
get info hy2 || true
info
[[ -z $is_hy2_obfs_type && $is_url != *'obfs='* && $is_url != *'obfs-password='* ]]
[[ $is_url == *':20000-30000?'* ]]
jq -e '.inbounds[0]|has("obfs")|not' "$is_conf_dir/$is_config_file" >/dev/null
cmp "$test_dir/hopping.conf" "$is_port_hopping_dir/$is_config_file.conf"

# The real change dispatcher and interactive enable/password defaults.
is_dont_auto_exit=1
change hy2 obfs on dispatcher-password >/dev/null || true
[[ $(jq -r '.inbounds[0].obfs.password' "$is_conf_dir/$is_config_file") == dispatcher-password ]]
printf '1\n\n' | hy2_obfs_change >/dev/null || true
[[ $(jq -r '.inbounds[0].obfs.password' "$is_conf_dir/$is_config_file") == dispatcher-password ]]
change hy2 obfs off >/dev/null || true
jq -e '.inbounds[0]|has("obfs")|not' "$is_conf_dir/$is_config_file" >/dev/null
get info hy2 || true
printf '1\n\n' | hy2_obfs_change >/dev/null || true
[[ $(jq -r '.inbounds[0].obfs.password' "$is_conf_dir/$is_config_file") == 1234567890abcdef1234567890abcdef ]]
unset is_dont_auto_exit

jq '.inbounds[0].type="trojan"' "$test_dir/original.json" >"$is_conf_dir/trojan-443.json"
is_protocol=trojan
hy2_obfs_load "$is_conf_dir/trojan-443.json"
net=trojan
is_dont_show_info=1
info
[[ " ${is_can_change[*]} " != *' 14 '* ]]
is_config_file=trojan-443.json
! hy2_obfs_apply on test
[[ -z $(find "$is_conf_dir" -name '.hy2-obfs*' -print) ]]
echo 'hy2-obfs tests passed'
