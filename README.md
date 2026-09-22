# Xray 交互式安装与管理脚本

这是一个面向 **Debian/Ubuntu** 和 **Alpine Linux** 的 Xray 管理脚本，支持创建和维护：

- VLESS + REALITY + XTLS Vision
- Shadowsocks 2022
- IPv4、IPv6、双栈 IPv6 优先
- v2rayN 分享链接
- 终端二维码
- 配置修改、重启、状态查看和安全卸载

项目地址：<https://github.com/GithubPlusMaxPro/xray_install>

## 安装和运行

使用 root 执行。推荐先下载脚本再运行，便于以后重复使用：

```bash
curl -fsSL https://raw.githubusercontent.com/GithubPlusMaxPro/xray_install/main/xray.sh -o xray.sh
chmod +x xray.sh
sh xray.sh
```

也可以直接运行：

```bash
curl -fsSL https://raw.githubusercontent.com/GithubPlusMaxPro/xray_install/main/xray.sh | sh
```

脚本会自动安装 Xray 和必要依赖。它不会自动创建任何 VLESS 或 SS2022 入站，只有在菜单中完成对应协议的配置并保存后，才会写入配置文件。

首次运行时，终端会打印当前进度，包括系统检测、依赖安装、Xray 下载与安装、配置初始化和服务启动。下载 Xray 时会显示进度条。

## 交互菜单

运行 `sh xray.sh` 后显示：

```text
1) 配置/修改 VLESS Reality
2) 配置/修改 Shadowsocks 2022
3) 重启 Xray
4) 查看状态
5) 查看节点和配置摘要
6) 卸载 Xray（可选择保留备份或清空）
0) 退出
```

配置完成后，脚本会询问是否立即重启 Xray。也可以稍后从菜单选择“重启 Xray”。

再次配置同一协议时，已有参数会作为默认值，可以修改端口、域名、加密方式和 IP 模式。配置另一个协议不会删除已经保存的协议。

## 配置选项

### VLESS Reality

脚本会询问：

- 服务器域名或 IP：只用于生成客户端分享链接
- VLESS 监听端口
- Reality 伪装目标 `域名` 或 `域名:端口`
- Reality SNI
- IP 模式
- 是否保留现有 UUID 和 Reality 密钥

如果不保留旧密钥，脚本会重新生成 UUID、Reality 私钥、公钥和 Short ID。保留旧密钥可以避免已经导入客户端的节点失效。

### Shadowsocks 2022

脚本会询问：

- 服务器域名或 IP：只用于生成客户端分享链接
- SS2022 监听端口
- 加密方式
- IP 模式
- 是否保留现有密码

支持的加密方式：

```text
2022-blake3-aes-128-gcm
2022-blake3-aes-256-gcm（推荐）
2022-blake3-chacha20-poly1305
```

### IP 模式

```text
dual   双栈监听，出站 IPv6 优先，失败回落 IPv4
ipv4   仅 IPv4
ipv6   仅 IPv6
```

双栈模式会使用 `UseIPv6v4`，监听地址为 `::`。这里控制的是 Xray 的监听和出站解析策略；客户端设备本身是否优先 IPv6，还取决于客户端系统、DNS 和网络运营商。

## 节点信息和二维码

配置完成后，终端会显示：

- v2rayN 可导入的 `vless://` 或 `ss://` 分享字符串
- 尝试直接显示的终端二维码
- VLESS 的公钥、Short ID 等参数
- SS2022 的加密方式和密码

菜单中的“查看节点和配置摘要”可以再次显示已保存节点。二维码只显示在终端，不会生成 PNG 或额外二维码文件。

如果系统没有 `qrencode`，分享字符串仍会正常显示。Debian/Ubuntu 会自动安装 `qrencode`；Alpine 会尝试安装可用的 `libqrencode-tools` 包。

## 命令行参数

```bash
sh xray.sh                            # 打开交互菜单
sh xray.sh --vless                    # 直接配置/修改 VLESS Reality
sh xray.sh --ss                       # 直接配置/修改 Shadowsocks 2022
sh xray.sh --restart                  # 重启 Xray
sh xray.sh --status                   # 查看 Xray 状态
sh xray.sh --help                    # 查看帮助
sh xray.sh --uninstall                # 交互确认后卸载
sh xray.sh --uninstall --yes          # 无交互卸载，默认保留备份
sh xray.sh --uninstall --purge --yes  # 无交互卸载并永久清空数据
```

`--purge` 会永久删除配置、节点信息和日志。没有同时指定 `--yes` 时，脚本仍会要求交互确认。

## 文件和服务

主要文件：

```text
/usr/local/bin/xray              Xray 内核
/usr/local/etc/xray/config.json  Xray 配置
/root/xray-nodes.json            节点参数和客户端信息
/var/log/xray/access.log         访问日志
/var/log/xray/error.log          错误日志
```

节点文件包含 Reality 私钥和 SS2022 密码，权限为 `600`，不要公开或提交到 Git 仓库。

每次修改配置前，旧配置会备份为：

```text
/usr/local/etc/xray/config.json.bak.时间戳
```

Debian/Ubuntu 使用 systemd 管理服务，Alpine 使用 OpenRC。配置完成后选择立即重启，或运行 `sh xray.sh --restart`，脚本会自动加入开机自启。

Debian/Ubuntu 实际执行的服务操作相当于：

```bash
systemctl enable xray
systemctl restart xray
```

Alpine 实际执行的服务操作相当于：

```bash
rc-update add xray default
rc-service xray restart
```

检查服务状态：

```bash
systemctl status xray       # Debian/Ubuntu
rc-service xray status      # Alpine
```

## 卸载和恢复

普通卸载不会直接删除数据：

```bash
sh xray.sh --uninstall
```

确认卸载后，脚本会继续询问是否清空数据。默认选择“不清空”，相关文件会移动到：

```text
/root/xray-uninstall-backup-YYYYMMDDHHMMSS/
```

备份内容包括配置、节点信息、日志、Xray 内核和服务文件。需要恢复时，可从该目录取回文件后重新安装或启动 Xray。

选择清空，或运行下面的命令，会永久删除这些数据，无法恢复：

```bash
sh xray.sh --uninstall --purge --yes
```

卸载不会删除系统通用依赖，例如 `curl`、`openssl`、`jq` 和 `qrencode`。

## 防火墙和端口

脚本不会自动修改云防火墙、iptables、nftables 或 UFW。请根据实际配置，在服务器安全组和防火墙中放行 VLESS、SS2022 使用的端口。

如果使用域名生成节点链接，请确认域名解析到了服务器，并且客户端能够访问对应端口。

## 安全提示

- 不要把 `/root/xray-nodes.json`、Reality 私钥或 SS2022 密码发布到 GitHub。
- 修改 Reality 私钥或 UUID 后，旧客户端节点需要重新导入。
- 卸载前如需保留节点，选择保留备份，不要使用 `--purge`。
