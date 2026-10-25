#!/bin/bash

# Hysteria2 port hopping for sing-box.
# sing-box listens on one UDP port; nftables/iptables redirects a public UDP
# range to that port. Metadata is kept outside conf/ so sing-box never parses it.

is_core_dir=${is_core_dir:-/etc/sing-box}
is_port_hopping_dir=${is_port_hopping_dir:-$is_core_dir/port-hopping}
is_port_hopping_table=sing_box_port_hopping

port_hopping_validate() {
    local range=$1 start end
    [[ $range =~ ^([1-9][0-9]{0,4})[-:]([1-9][0-9]{0,4})$ ]] || return 1
    start=${BASH_REMATCH[1]}
    end=${BASH_REMATCH[2]}
    ((start <= 65535 && end <= 65535 && start < end)) || return 1
    echo "$start-$end"
}

port_hopping_require_backend() {
    type -P nft &>/dev/null || type -P iptables &>/dev/null || {
        echo "错误: HY2 端口跳跃需要 nftables 或 iptables。" >&2
        return 1
    }
}

port_hopping_meta_file() {
    local config_name=$1
    [[ $config_name =~ ^[A-Za-z0-9._-]+$ ]] || return 1
    echo "$is_port_hopping_dir/$config_name.conf"
}

port_hopping_save() {
    local config_name=$1 target_port=$2 range=$3 meta_file start end
    range=$(port_hopping_validate "$range") || return 1
    [[ $target_port =~ ^[1-9][0-9]{0,4}$ ]] && ((target_port <= 65535)) || return 1
    meta_file=$(port_hopping_meta_file "$config_name") || return 1
    IFS=- read -r start end <<<"$range"
    mkdir -p "$is_port_hopping_dir"
    printf 'TARGET_PORT=%s\nHOP_START=%s\nHOP_END=%s\n' "$target_port" "$start" "$end" >"$meta_file"
}

port_hopping_load() {
    local config_name=$1 meta_file key value
    unset is_hop_range is_hop_target_port is_hop_start is_hop_end
    meta_file=$(port_hopping_meta_file "$config_name") || return 1
    [[ -f $meta_file ]] || return 0
    while IFS='=' read -r key value; do
        case $key in
        TARGET_PORT) is_hop_target_port=$value ;;
        HOP_START) is_hop_start=$value ;;
        HOP_END) is_hop_end=$value ;;
        esac
    done <"$meta_file"
    is_hop_range=$(port_hopping_validate "$is_hop_start-$is_hop_end") || {
        unset is_hop_range is_hop_target_port is_hop_start is_hop_end
        return 1
    }
    [[ $is_hop_target_port =~ ^[1-9][0-9]{0,4}$ ]] && ((is_hop_target_port <= 65535)) || return 1
}

port_hopping_remove() {
    local meta_file
    meta_file=$(port_hopping_meta_file "$1") || return 1
    rm -f "$meta_file"
}

port_hopping_clear_nft() {
    type -P nft &>/dev/null || return 0
    nft list table inet "$is_port_hopping_table" &>/dev/null && \
        nft delete table inet "$is_port_hopping_table" &>/dev/null
    return 0
}

port_hopping_clear_iptables() {
    local family start end target
    [[ -f $is_port_hopping_dir/.applied ]] || return 0
    while IFS='|' read -r start end target; do
        [[ $start && $end && $target ]] || continue
        for family in iptables ip6tables; do
            type -P "$family" &>/dev/null || continue
            while "$family" -w -t nat -C PREROUTING -p udp --dport "$start:$end" -j REDIRECT --to-ports "$target" &>/dev/null; do
                "$family" -w -t nat -D PREROUTING -p udp --dport "$start:$end" -j REDIRECT --to-ports "$target" &>/dev/null || break
            done
        done
    done <"$is_port_hopping_dir/.applied"
    rm -f "$is_port_hopping_dir/.applied"
}

port_hopping_read_meta() {
    local meta_file=$1 key value
    unset hop_target hop_start hop_end
    while IFS='=' read -r key value; do
        case $key in
        TARGET_PORT) hop_target=$value ;;
        HOP_START) hop_start=$value ;;
        HOP_END) hop_end=$value ;;
        esac
    done <"$meta_file"
    port_hopping_validate "$hop_start-$hop_end" &>/dev/null || return 1
    [[ $hop_target =~ ^[1-9][0-9]{0,4}$ ]] && ((hop_target <= 65535))
}

port_hopping_apply_nft() {
    local meta_file rules_file found= nft_bin
    nft_bin=$(type -P nft) || return 1
    rules_file=$(mktemp) || return 1
    printf 'table inet %s {\n  chain prerouting {\n    type nat hook prerouting priority dstnat; policy accept;\n' "$is_port_hopping_table" >"$rules_file"
    for meta_file in "$is_port_hopping_dir"/*.conf; do
        [[ -f $meta_file ]] || continue
        port_hopping_read_meta "$meta_file" || continue
        printf '    udp dport %s-%s redirect to :%s comment "sing-box-hy2"\n' "$hop_start" "$hop_end" "$hop_target" >>"$rules_file"
        found=1
    done
    printf '  }\n}\n' >>"$rules_file"
    [[ $found ]] || {
        rm -f "$rules_file"
        return 0
    }
    "$nft_bin" -f "$rules_file"
    local status=$?
    rm -f "$rules_file"
    return $status
}

port_hopping_apply_iptables() {
    local meta_file family found=
    type -P iptables &>/dev/null || return 1
    : >"$is_port_hopping_dir/.applied"
    for meta_file in "$is_port_hopping_dir"/*.conf; do
        [[ -f $meta_file ]] || continue
        port_hopping_read_meta "$meta_file" || continue
        if ! iptables -w -t nat -A PREROUTING -p udp --dport "$hop_start:$hop_end" -j REDIRECT --to-ports "$hop_target"; then
            port_hopping_clear_iptables
            return 1
        fi
        if type -P ip6tables &>/dev/null; then
            ip6tables -w -t nat -A PREROUTING -p udp --dport "$hop_start:$hop_end" -j REDIRECT --to-ports "$hop_target" 2>/dev/null || true
        fi
        printf '%s|%s|%s\n' "$hop_start" "$hop_end" "$hop_target" >>"$is_port_hopping_dir/.applied"
        found=1
    done
    [[ $found ]] || rm -f "$is_port_hopping_dir/.applied"
}

port_hopping_apply_all() {
    mkdir -p "$is_port_hopping_dir"
    port_hopping_clear_iptables
    port_hopping_clear_nft
    if type -P nft &>/dev/null; then
        port_hopping_apply_nft && return 0
        echo "警告: nftables 规则应用失败，尝试 iptables。" >&2
        port_hopping_clear_nft
    fi
    if type -P iptables &>/dev/null; then
        port_hopping_apply_iptables
    elif compgen -G "$is_port_hopping_dir/*.conf" &>/dev/null; then
        port_hopping_require_backend
    fi
}

port_hopping_clear() {
    mkdir -p "$is_port_hopping_dir"
    port_hopping_clear_iptables
    port_hopping_clear_nft
}

port_hopping_install_boot_service() {
    if type -P systemctl &>/dev/null; then
        printf '%s\n' \
            '[Unit]' \
            'Description=sing-box Hysteria2 port hopping' \
            'After=network-pre.target' \
            'Before=sing-box.service' \
            '' \
            '[Service]' \
            'Type=oneshot' \
            'RemainAfterExit=yes' \
            "ExecStart=/bin/bash $is_core_dir/sh/src/port-hopping.sh apply-all" \
            "ExecStop=/bin/bash $is_core_dir/sh/src/port-hopping.sh clear" \
            '' \
            '[Install]' \
            'WantedBy=multi-user.target' >'/etc/systemd/system/sing-box-port-hopping.service'
        systemctl daemon-reload
        systemctl enable sing-box-port-hopping.service &>/dev/null
    elif type -P rc-update &>/dev/null; then
        printf '%s\n' \
            '#!/sbin/openrc-run' \
            'name="sing-box Hysteria2 port hopping"' \
            'description="Restore HY2 UDP port hopping rules"' \
            'depend() { need net; before sing-box; }' \
            "start() { /bin/bash $is_core_dir/sh/src/port-hopping.sh apply-all; }" \
            "stop() { /bin/bash $is_core_dir/sh/src/port-hopping.sh clear; }" >'/etc/init.d/sing-box-port-hopping'
        chmod +x /etc/init.d/sing-box-port-hopping
        rc-update add sing-box-port-hopping default &>/dev/null
    fi
}

port_hopping_uninstall() {
    port_hopping_clear
    if type -P systemctl &>/dev/null; then
        systemctl disable sing-box-port-hopping.service &>/dev/null || true
        rm -f /etc/systemd/system/sing-box-port-hopping.service
        systemctl daemon-reload &>/dev/null || true
    fi
    if type -P rc-update &>/dev/null; then
        rc-update del sing-box-port-hopping default &>/dev/null || true
        rm -f /etc/init.d/sing-box-port-hopping
    fi
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    case $1 in
    apply-all) port_hopping_apply_all ;;
    clear) port_hopping_clear ;;
    *) echo "Usage: $0 {apply-all|clear}" >&2; exit 2 ;;
    esac
fi
