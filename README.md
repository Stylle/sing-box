# sing-box 管理脚本

本仓库 fork 自 [233boy/sing-box](https://github.com/233boy/sing-box)，保留上游功能，并为 Hysteria2 增加端口跳跃创建、修改、显示、删除与开机恢复。

## 安装

```bash
bash <(wget -qO- https://raw.githubusercontent.com/Stylle/sing-box/main/install.sh)
```

脚本默认从 `Stylle/sing-box` 的 `main` 分支自更新，避免 `sing-box update sh` 切回上游版本而丢失端口跳跃功能。

已有旧版或上游脚本时，先只替换管理脚本（不会修改核心和配置）：

```bash
bash <(wget -qO- https://raw.githubusercontent.com/Stylle/sing-box/main/install.sh) --script-only
```

## HY2 端口跳跃

```bash
# 监听 UDP 443，对外开放并跳跃 20000-30000
sing-box add hy2 443 'your-password' 20000-30000

# 查看分享链接和配置
sing-box info hy2

# 修改范围或关闭
sing-box change hy2 hop 30000-40000
sing-box change hy2 hop off
```

## HY2 混淆开关

运行 `sing-box` → **更改配置** → 选择 HY2 → **开启 / 关闭 HY2 混淆**。支持开启 Salamander、更换密码、关闭；密码留空时保留已有密码，没有则自动生成。默认不启用。

```bash
# 交互设置
sing-box change hy2 obfs
# 开启并设置独立的混淆密码
sing-box change hy2 obfs on 'your-obfs-password'
# 关闭
sing-box change hy2 obfs off
```

修改前校验，重启失败恢复原配置；端口跳跃、认证密码和 TLS 配置不变。分享链接自动携带 `obfs` / `obfs-password`，查看配置显示开关状态；更改端口、认证密码或跳跃范围时保留混淆。客户端必须重新导入新链接，两端设置不一致将无法连接。多个 HY2 时用配置文件名替换 `hy2`。

## UFW 防火墙

主菜单进入“其他” → “HY2端口跳跃-UFW”，可以查看、一键放开或一键关闭脚本控制的 UDP 范围。也可以直接运行：

```bash
sing-box ufw open
sing-box ufw status
sing-box ufw close
```

脚本会同时放行公开跳跃范围和 sing-box 实际监听的 UDP 端口，并给自己创建的规则添加标记、单独记录，只删除自己创建的规则。如果相同端口已经由你手动放行，脚本会跳过且不会接管。开启脚本 UFW 管理后，新增、删除或修改 HY2 跳跃范围会自动同步。

为避免启用 UFW 时误封 SSH，`open` 只添加放行规则，不会自动执行 `ufw enable`。如果 `ufw status` 显示 inactive，需要你确认 SSH 等必要端口已经放行后再自行启用 UFW。

也可以直接运行 `sing-box`，在交互式创建 Hysteria2 时填写范围。端口跳跃需要 Linux 已安装 `nftables` 或 `iptables`，并需要在系统防火墙及云服务商安全组中放行整个 UDP 范围。sing-box 本身仍只监听创建时指定的单端口。

客户端分享 URI 使用 Hysteria2 标准多端口格式。sing-box 客户端配置可使用：

```json
{
  "type": "hysteria2",
  "server": "example.com",
  "server_ports": ["20000:30000"],
  "hop_interval": "30s"
}
```

`server_ports` 需要 sing-box 1.11.0 或更高版本。

## 更新关系

- `233boy/sing-box`：GitHub Actions 每天自动合并上游 `main`，也可在 Actions 中手动运行 `Sync upstream`。
- 自定义功能：采用 merge，不会强制覆盖；发生冲突时任务失败并创建 Issue，等待人工解决。
- 管理脚本：服务器执行 `sing-box update sh`，直接获取本 fork 的最新 `main`。
- sing-box 核心：服务器执行 `sing-box update core`，仍直接获取 `SagerNet/sing-box` 最新发行版。

自动同步无法承诺永远无冲突，但它能保证冲突时停止，而不是悄悄删除端口跳跃代码。

## 常用命令

```bash
sing-box help
sing-box update sh
sing-box update core
sing-box status
sing-box restart
```

端口跳跃参考：[Hysteria 2 Port Hopping](https://v2.hysteria.network/docs/advanced/Port-Hopping/)；客户端字段参考：[sing-box Hysteria2 outbound](https://sing-box.sagernet.org/configuration/outbound/hysteria2/)。
