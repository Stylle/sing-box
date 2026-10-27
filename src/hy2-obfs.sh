#!/bin/bash

# Keep obfuscation in the inbound itself; no sidecar state can get out of sync.
hy2_obfs_load() {
    unset is_hy2_obfs_json is_hy2_obfs_type is_hy2_obfs_password
    [[ ${is_protocol:-} == hysteria2 ]] || return 0
    is_hy2_obfs_json=$(jq -c '.inbounds[0].obfs // empty' "$1") || return 1
    [[ $is_hy2_obfs_json ]] || return 0
    is_hy2_obfs_type=$(jq -r '.type // empty' <<<"$is_hy2_obfs_json")
    is_hy2_obfs_password=$(jq -r '.password // empty' <<<"$is_hy2_obfs_json")
}

hy2_obfs_restart() {
    if [[ ${is_systemd:-} ]]; then
        timeout 25 systemctl restart "$is_core" || return 1
    elif [[ ${is_openrc:-} ]]; then
        timeout 25 rc-service "$is_core" restart || return 1
    else
        return 1
    fi
    # Don't rebuild hopping rules here: this edit never changes ports or
    # hopping metadata, and netfilter rules survive a core-only restart.
    sleep 2
    pgrep -f "$is_core_bin" >/dev/null
}

# Transactional edit: don't recreate the inbound or alter hopping/firewall state.
hy2_obfs_apply() (
    local mode=$1 secret=${2:-} source_file="$is_conf_dir/$is_config_file"
    local candidate backup remove_backup=1
    type -P timeout >/dev/null || {
        echo "缺少 timeout 命令，请安装 coreutils 后重试；原配置未修改。" >&2
        return 1
    }
    case $mode in
    on)
        jq -en --arg password "$secret" '$password | length > 0 and length <= 256 and (test("[\\x00-\\x1f\\x7f]") | not)' >/dev/null || {
            echo "混淆密码必须为 1–256 个字符，不能包含控制字符。" >&2
            return 1
        }
        ;;
    off) ;;
    *) echo "混淆选项仅支持 on / off。" >&2; return 1 ;;
    esac
    [[ -f $source_file && ! -L $source_file ]] || return 1
    jq -e '.inbounds[0].type == "hysteria2"' "$source_file" >/dev/null || {
        echo "只有 HY2 配置支持此混淆开关。" >&2
        return 1
    }
    umask 077
    candidate=$(mktemp "$is_conf_dir/.hy2-obfs.XXXXXX") || return 1
    backup=$(mktemp "$is_conf_dir/.hy2-obfs-backup.XXXXXX") || { rm -f -- "$candidate"; return 1; }
    trap 'rm -f -- "$candidate"; if [[ $remove_backup == 1 ]]; then rm -f -- "$backup"; fi' EXIT
    cp -p -- "$source_file" "$backup" || return 1
    chmod 600 "$backup" || return 1
    if [[ $mode == on ]]; then
        jq --arg password "$secret" '.inbounds[0].obfs = {type:"salamander",password:$password}' "$backup" >"$candidate" || return 1
    else
        jq 'del(.inbounds[0].obfs)' "$backup" >"$candidate" || return 1
    fi
    echo "[1/3] 正在校验新配置（最多 20 秒）…"
    timeout 20 "$is_core_bin" check -c "$candidate" >/dev/null 2>&1 || {
        echo "新配置校验失败或超时，原配置未修改。" >&2
        return 1
    }
    cmp -s -- "$source_file" "$backup" || {
        echo "配置被其他操作修改，请重新执行。" >&2
        return 1
    }
    chmod 600 "$candidate" || return 1
    mv -f -- "$candidate" "$source_file" || return 1
    echo "[2/3] 正在重启 sing-box（最多 25 秒）…"
    if ! hy2_obfs_restart; then
        echo "重启失败或超时，正在恢复原配置…" >&2
        if ! mv -f -- "$backup" "$source_file"; then
            remove_backup=0
            echo "恢复配置失败，原文件保存在：$backup" >&2
            return 1
        fi
        hy2_obfs_restart || echo "原配置已恢复，但服务仍未启动，请查看运行日志。" >&2
        echo "混淆切换后服务启动失败，已恢复原配置。" >&2
        return 1
    fi
    echo "[3/3] sing-box 已就绪，正在生成分享链接…"
)

hy2_obfs_change() {
    local mode=${1:-} secret=${2:-}
    mode=${mode,,}
    [[ ${is_protocol:-} == hysteria2 ]] || { err "只有 HY2 配置支持混淆开关。"; return 1; }
    if [[ ! $mode ]]; then
        msg "\n当前 HY2 混淆：${is_hy2_obfs_type:-关闭}"
        printf '%s\n' '1) 开启 Salamander / 修改密码' '2) 关闭混淆' '0) 返回（不修改配置）' '请输入选项并回车：'
        read -r mode || { warn "未读取到输入，已取消；原配置未修改。"; return 1; }
    fi
    case $mode in
    1 | on | enable | salamander)
        mode=on
        if [[ ! $secret ]]; then
            printf '%s\n' '请输入混淆密码并回车（留空保留现有密码，未设置则自动生成）：'
            read -r secret || { warn "未读取到密码输入，已取消；原配置未修改。"; return 1; }
            [[ $secret ]] || secret=${is_hy2_obfs_password:-}
        fi
        if [[ ! $secret ]]; then
            secret=$(openssl rand -hex 16) || { err "生成混淆密码失败。"; return 1; }
        fi
        ;;
    2 | off | disable | none) mode=off ;;
    0 | cancel) return 0 ;;
    *) err "请选择开启或关闭混淆。"; return 1 ;;
    esac
    hy2_obfs_apply "$mode" "$secret" || { err "HY2 混淆设置未生效，请检查上方错误。"; return 1; }
    # Reload for both information display and URI generation after the edit.
    get info "$is_config_file"
    is_dont_show_info=
    info
    if [[ $mode == on ]]; then
        msg "\nHY2 Salamander 混淆已开启。"
    else
        msg "\nHY2 混淆已关闭。"
    fi
    msg "客户端必须同步更新，请重新导入上面的分享链接。"
}
