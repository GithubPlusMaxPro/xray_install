# Xray VLESS REALITY + Shadowsocks 2022 一键脚本

支持 Debian/Ubuntu（systemd）和 Alpine（OpenRC）。脚本使用 XTLS/Xray-install 官方安装脚本安装或升级 Xray，然后生成：

- VLESS + REALITY + XTLS Vision
- Shadowsocks 2022（默认 `2022-blake3-aes-256-gcm`）
- Freedom 出站 `UseIPv6v4`：优先 IPv6，失败回落 IPv4

脚本不会自动修改云厂商安全组、iptables、nftables 或 UFW 规则。请自行放行所选端口。

## 使用

直接在服务器上运行脚本时会进入交互模式，可以依次填写服务器域名/IP、端口、REALITY 伪装域名、SS2022 加密方式和 IP 模式：

```bash
sh xray-vless-reality-ss2022.sh
```

也可以显式指定交互模式：

```bash
sh xray-vless-reality-ss2022.sh --interactive
```

IP 模式有三种：

- `dual`：双栈监听，域名解析 IPv6 优先，失败回落 IPv4
- `ipv4`：仅 IPv4 监听和出站
- `ipv6`：仅 IPv6 监听和出站

脚本也支持非交互方式：

```bash
curl -fsSL https://raw.githubusercontent.com/GithubPlusMaxPro/xray_install/main/xray-vless-reality-ss2022.sh \
  | sh -s -- --server-address 你的服务器地址 --ip-mode dual --force
```

默认创建：

- VLESS REALITY：`443`
- SS2022：`8388`
- REALITY 目标：`www.apple.com:443`

建议显式指定 REALITY 目标和服务器地址：

```bash
sh xray-vless-reality-ss2022.sh \
  --server-address 2001:db8::1 \
  --target www.apple.com:443 \
  --force
```

只创建一种协议：

```bash
sh xray-vless-reality-ss2022.sh --only-vless --vless-port 52011 --force
sh xray-vless-reality-ss2022.sh --only-ss --ss-port 8388 --force
sh xray-vless-reality-ss2022.sh --ss-method 2022-blake3-chacha20-poly1305 --force
```

如果系统已经安装 Xray，脚本默认复用现有内核；需要升级时添加 `--upgrade`。

## 生成文件

Xray 配置：

```text
/usr/local/etc/xray/config.json
```

客户端参数（权限 600）：

```text
/root/xray-credentials.txt
```

服务管理：

```bash
# Debian/Ubuntu
systemctl status xray
systemctl restart xray

# Alpine
rc-service xray status
rc-service xray restart
```

## 注意

1. `--force` 会覆盖现有 Xray 配置，但会先生成时间戳备份。
2. REALITY 的目标站点应选择稳定、支持 TLS 的站点；不要把脚本默认目标当作固定要求。
3. `xray-credentials.txt` 包含私密密钥和 SS 密码，不要提交到 GitHub。
4. 如果使用 IPv6 地址生成客户端链接，脚本会自动加方括号；域名则不加。
