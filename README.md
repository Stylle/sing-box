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
