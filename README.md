# Xray 一键安装与管理脚本

适用于 Debian、Ubuntu 和 Alpine。脚本可以创建：

- VLESS Reality
- Shadowsocks 2022
- Hysteria2
- VLESS XHTTP

配置完成后，终端会显示节点分享链接和二维码。

## 一、安装

使用 `root` 登录服务器，执行：

```bash
curl -fsSL https://raw.githubusercontent.com/GithubPlusMaxPro/xray_install/main/xray.sh -o xray.sh
chmod +x xray.sh
sh xray.sh
```

建议先下载再运行，之后可以重复使用这个脚本。

也可以直接运行：

```bash
curl -fsSL https://raw.githubusercontent.com/GithubPlusMaxPro/xray_install/main/xray.sh | sh
```

首次运行会检查系统、安装所需软件、安装 Xray 并启动管理菜单。脚本不会自动创建 VLESS、SS2022、Hysteria2 或 VLESS XHTTP 节点，选择对应菜单并保存后才会创建。

## 二、菜单

运行 `sh xray.sh` 后，会看到：

```text
1) 配置/修改 VLESS Reality
2) 配置/修改 Shadowsocks 2022
3) 配置/修改 Hysteria2
4) 配置/修改 VLESS XHTTP
5) 重启 Xray
6) 查看状态
7) 查看节点和配置摘要
8) 卸载 Xray（可选择保留备份或清空）
9) 编辑 Xray 配置文件
10) 删除 VLESS Reality、Shadowsocks 2022、Hysteria2 或 VLESS XHTTP
11) 出站与出口路由设置（IP 模式 / SOCKS5 WARP）
0) 退出
```

## 三、创建 VLESS Reality

1. 选择 `1`。
2. 按提示填写服务器域名或公网 IP。
3. 填写端口。
4. 填写 Reality 伪装目标和 SNI。
5. 按提示确认保存并重启。

如果已经配置过，再次进入时会自动显示原来的内容，直接回车即可保留。

服务器地址要填写客户端能访问的域名或公网 IP，不要填写 `192.168.x.x`、`10.x.x.x` 等内网地址。

配置时会询问：

- 服务器域名或 IP
- VLESS 端口
- Reality 伪装目标
- Reality SNI
- 是否保留现有 UUID 和 Reality 密钥

如果重新生成 UUID 或 Reality 密钥，已经导入客户端的旧节点需要重新导入。

### 创建 VLESS XHTTP

1. 选择 `4`（或直接运行 `sh xray.sh --xhttp`）。
2. 填写服务器域名或公网 IP、端口、XHTTP 路径（默认随机生成）以及可选的 Host。
3. 选择 XHTTP 传输模式：
   - `auto`：自动协商（推荐）
   - `packet-up`：分包上行，CDN/反代兼容性最好
   - `stream-up`：流式上行，上下行分离
   - `stream-one`：单连接双向流
4. 选择传输安全模式：
   - `reality`：无需证书，适合直连（按提示填写伪装目标和 SNI）
   - `tls`：使用已有 TLS 证书（填写 SNI、证书和私钥路径，可选配置信任的 XFF 头部）
   - `none`：无 TLS，默认监听 `127.0.0.1`，适合配合 Nginx/Caddy/CDN 反代（可选配置信任的 XFF 头部）
5. 保存并重启。

VLESS XHTTP 入站不使用 `xtls-rprx-vision` flow，脚本会自动生成标准 `type=xhttp` 分享链接与二维码。如需设置 `xhttpSettings.extra`（如 `xmux` 或 `downloadSettings`），可通过菜单 `9` 编辑配置文件；查看节点摘要时会自动把 `extra` 编码进分享链接。

## 四、创建 Shadowsocks 2022

1. 选择 `2`。
2. 填写服务器域名或公网 IP。
3. 填写端口。
4. 选择加密方式。
5. 确认保存并重启。

脚本会自动生成密码，也可以在再次配置时修改密码。

可选加密方式：

```text
2022-blake3-aes-128-gcm
2022-blake3-aes-256-gcm
2022-blake3-chacha20-poly1305
```

## 五、创建 Hysteria2

1. 选择 `3`。
2. 填写服务器域名或公网 IP。
3. 填写 UDP 端口。
4. 填写证书域名。
5. 填写证书完整路径。
6. 填写私钥完整路径。
7. 设置密码。
8. 可选填写端口跳跃范围（如 `20000-50000`；留空则不启用）。
9. 保存并重启。

证书需要提前准备好。例如：

```text
/etc/ssl/xray/fullchain.pem
/etc/ssl/xray/privkey.pem
```

脚本只读取你填写的证书，不会自动申请证书。使用 Hysteria2 时，要在云服务器安全组和系统防火墙放行对应的 UDP 端口；若启用了端口跳跃，脚本会自动在分享链接中加入 `mport` 参数并输出对应的 `nftables` / `iptables` UDP 转发参考命令，请按需执行并放行相应 UDP 端口段。

## 六、出站与出口路由设置

在菜单选择 `11`（或执行 `sh xray.sh --outbound`），可统一管理出站策略与出口路由：

### 1. Freedom 直连出站 IP 模式

选择子菜单 `1`，可以单独设置所有 `freedom` 直连出站的域名解析策略。配置 VLESS、SS2022、Hysteria2 或 VLESS XHTTP 时不会修改这项设置。该策略控制 Xray 连接目标域名时使用的地址族，不限制节点入站监听地址；脚本创建的入站默认监听 `::`（XHTTP `none` 模式默认 `127.0.0.1`），允许 IPv4 和 IPv6 连接。

```text
UseIPv6v4  优先使用 IPv6 解析结果；无结果时尝试 IPv4
UseIPv4    使用 IPv4 解析结果
UseIPv6    使用 IPv6 解析结果
AsIs       使用 Xray 默认解析方式
```

一般双栈服务器可以选择 `UseIPv6v4`。没有 IPv6 出站能力时选择 `UseIPv4`；只有 IPv6 出站能力时选择 `UseIPv6`。这个选择不会关闭 IPv4 入站。

### 2. SOCKS5 / WARP 出口路由

选择子菜单 `2`（或直接运行 `sh xray.sh --warp`），可添加 `tag` 为 `warp` 的 SOCKS5 出站（默认 `127.0.0.1:40000`），并选择：

- 全局走 `warp` 出口
- 按域名/geosite 分流走 `warp`（如 `geosite:openai,geosite:netflix`，其余走直连）
- 仅添加 `warp` 出站，不修改路由规则
- 移除 `warp` 出站及对应路由规则

如需在本机部署 WARP SOCKS5 代理，可先执行：

```bash
wget -N https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh && bash menu.sh
```

### 3. 自定义出站（JSON）

选择子菜单 `3`，可查看、添加/修改或删除自定义出站对象：

- 添加时会打开编辑器并预填标准出站 JSON 模板（默认 `socks` 模板），可直接粘贴任意合法的 Xray 出站 JSON（需包含 `protocol` 和 `tag`）；
- 保存后自动合并进 `outbounds`（同 `tag` 自动覆盖）并执行 `xray run -test` 校验；
- 删除指定 `tag` 的出站时，会自动清理指向该 `tag` 的路由规则。

### 4. 自定义路由规则（`routing.rules`）

选择子菜单 `4`，可查看、添加、删除或清空 `routing.rules` 路由规则：

- 支持按目标出站 `tag`（如 `direct`、`block`、`warp` 或自定义出站）分流；
- 支持组合匹配条件：域名/`geosite`、IP/CIDR/`geoip`、端口、网络协议（`tcp`/`udp`）、来源入站 `tag`；
- 支持选择插入到规则最前面（最高优先级）或末尾，保存前自动执行 `xray run -test` 校验。

## 七、查看节点和二维码

选择菜单 `7`，脚本会显示：

- VLESS 分享链接
- SS2022 分享链接
- Hysteria2 分享链接
- VLESS XHTTP 分享链接
- 终端二维码

在 v2rayN 等客户端中，可以直接复制分享链接导入。二维码只在当前终端显示，不会生成图片文件。

如果没有安装二维码工具，分享链接仍会正常显示。Debian/Ubuntu 会自动安装二维码工具；Alpine 会在软件源支持时尝试安装。

## 八、常用操作

### 重启

选择菜单 `5`，或执行：

```bash
sh xray.sh --restart
```

也可以直接使用系统服务命令：

Debian/Ubuntu：

```bash
systemctl restart xray
systemctl status xray
```

Alpine：

```bash
rc-service xray restart
rc-service xray status
```

配置完成后脚本会自动设置开机启动：

- Debian/Ubuntu 使用 `systemd`，服务名是 `xray`。
- Alpine 使用 `OpenRC`，服务名是 `xray`。

如果需要手动设置开机启动：

Debian/Ubuntu：

```bash
systemctl enable xray
```

Alpine：

```bash
rc-update add xray default
```

### 查看运行进程

```bash
ps -ef | grep '[x]ray'
```

正常运行时，可以看到 `/usr/local/bin/xray` 进程。

两个系统实际启动的程序都是 Xray，启动方式不同：

- Debian/Ubuntu：`/usr/local/bin/xray run -config /usr/local/etc/xray/config.json`
- Alpine：`/usr/local/bin/xray run -confdir /usr/local/etc/xray/`

查看端口是否正在监听：

```bash
ss -lntup | grep xray
```

### 查看日志

Debian/Ubuntu 还可以查看服务日志：

```bash
journalctl -u xray -f
```

通用日志文件：

```bash
tail -f /var/log/xray/error.log
tail -f /var/log/xray/access.log
```

### 查看状态

选择菜单 `6`，或执行：

```bash
sh xray.sh --status
```

### 编辑配置

选择菜单 `9`，或执行：

```bash
sh xray.sh --edit
```

编辑完成后按编辑器提示保存并退出。脚本会检查配置，检查失败时不会替换原配置。

### 删除节点

选择菜单 `10`，然后选择要删除的协议。删除一个协议不会影响其他协议。

也可以直接删除：

```bash
sh xray.sh --remove-vless
sh xray.sh --remove-ss
sh xray.sh --remove-hy2
sh xray.sh --remove-xhttp
```

### 直接进入配置

```bash
sh xray.sh --vless
sh xray.sh --ss
sh xray.sh --hy2
sh xray.sh --xhttp
```

### 全部命令

```bash
sh xray.sh                            # 打开交互菜单
sh xray.sh --vless                    # 直接配置/修改 VLESS Reality
sh xray.sh --ss                       # 直接配置/修改 Shadowsocks 2022
sh xray.sh --hy2                      # 直接配置/修改 Hysteria2
sh xray.sh --xhttp                    # 直接配置/修改 VLESS XHTTP
sh xray.sh --outbound                 # 出站与出口路由设置（IP 模式 / SOCKS5 WARP）
sh xray.sh --warp                     # 直接配置 SOCKS5 / WARP 出口路由
sh xray.sh --edit                     # 编辑并检查 Xray 配置文件
sh xray.sh --remove                   # 交互选择并删除协议
sh xray.sh --remove-vless             # 删除 VLESS Reality 入站
sh xray.sh --remove-ss                # 删除 Shadowsocks 2022 入站
sh xray.sh --remove-hy2               # 删除 Hysteria2 入站
sh xray.sh --remove-xhttp             # 删除 VLESS XHTTP 入站
sh xray.sh --restart                  # 重启 Xray
sh xray.sh --status                   # 查看 Xray 状态
sh xray.sh --help                     # 查看帮助
sh xray.sh --uninstall                # 交互确认后卸载
sh xray.sh --uninstall --yes          # 无交互卸载，默认保留备份
sh xray.sh --uninstall --purge --yes  # 无交互卸载并永久清空数据
```

## 九、文件位置

常用文件如下：

```text
/usr/local/bin/xray              Xray 主程序
/usr/local/etc/xray/config.json  Xray 配置文件
/root/xray-nodes.json            节点信息和分享链接
/var/log/xray/access.log         访问日志
/var/log/xray/error.log          错误日志
```

服务文件位置：

```text
/etc/systemd/system/xray.service   Debian/Ubuntu
/etc/init.d/xray                   Alpine
```

节点信息包含密码和密钥，请不要公开或上传到 GitHub。

节点文件权限为 `600`，只有 root 可以读取。不要把 Reality 私钥、SS2022 密码或 Hysteria2 密码发给别人。

修改节点时，脚本会先生成临时配置并检查 Xray 配置。检查通过后才会替换正式配置；检查失败时原配置不会改变。脚本不会为每次修改自动保存旧配置副本。

编辑配置时，菜单第 `9` 项和下面的命令都使用临时文件：

```bash
sh xray.sh --edit
```

只有保存并通过检查后，临时文件才会覆盖正式配置。编辑器按以下顺序选择：`$EDITOR`、`vim`、`nvim`、`vi`、`nano`。

如果手动修改配置后 Xray 无法启动，可以先执行：

```bash
sh xray.sh --edit
```

然后保存一个有效配置，再重启服务。

## 十、卸载

执行：

```bash
sh xray.sh --uninstall
```

卸载时可以选择：

- 保留配置、节点信息和日志
- 清空所有数据

建议第一次卸载时选择保留，方便以后恢复。选择清空后无法恢复。

选择保留时，文件会移动到下面的备份目录：

```text
/root/xray-uninstall-backup-YYYYMMDDHHMMSS/
```

如果确定不要任何数据，可以执行：

```bash
sh xray.sh --uninstall --purge --yes
```

## 十一、开机启动

配置完成并重启后，Xray 会加入系统开机启动。服务器重启后会自动运行。

Debian/Ubuntu：

```bash
systemctl enable xray
systemctl restart xray
```

Alpine：

```bash
rc-update add xray default
rc-service xray restart
```

## 十二、更新脚本

重新下载即可：

```bash
curl -fsSL https://raw.githubusercontent.com/GithubPlusMaxPro/xray_install/main/xray.sh -o xray.sh
chmod +x xray.sh
```

## 十三、端口检查

如果客户端无法连接，请检查：

1. 域名是否解析到服务器公网 IP。
2. 云服务器安全组是否放行端口。
3. 系统防火墙是否放行端口。
4. Hysteria2 是否放行了 UDP，而不是只放行 TCP。
5. 节点中的地址、端口、密码和证书域名是否填写正确。

服务器地址输入框会优先读取当前网卡地址。如果服务器在 NAT、容器或内网环境中，自动读取的可能是内网地址，这时请手动改成客户端可以访问的公网 IP 或域名。

项目地址：<https://github.com/GithubPlusMaxPro/xray_install>


