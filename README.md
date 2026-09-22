# Xray 一键安装与管理脚本

适用于 Debian、Ubuntu 和 Alpine。脚本可以创建：

- VLESS Reality
- Shadowsocks 2022
- Hysteria2

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

## 二、菜单

运行 `sh xray.sh` 后，会看到：

```text
1) 配置/修改 VLESS Reality
2) 配置/修改 Shadowsocks 2022
3) 重启 Xray
4) 查看状态
5) 查看节点和配置摘要
6) 卸载 Xray
7) 编辑 Xray 配置文件
8) 删除节点
9) 配置/修改 Hysteria2
0) 退出
```

## 三、创建 VLESS Reality

1. 选择 `1`。
2. 按提示填写服务器域名或公网 IP。
3. 填写端口。
4. 填写 Reality 伪装目标和 SNI。
5. 选择 IP 模式。
6. 按提示确认保存并重启。

如果已经配置过，再次进入时会自动显示原来的内容，直接回车即可保留。

服务器地址要填写客户端能访问的域名或公网 IP，不要填写 `192.168.x.x`、`10.x.x.x` 等内网地址。

## 四、创建 Shadowsocks 2022

1. 选择 `2`。
2. 填写服务器域名或公网 IP。
3. 填写端口。
4. 选择加密方式。
5. 选择 IP 模式。
6. 确认保存并重启。

脚本会自动生成密码，也可以在再次配置时修改密码。

## 五、创建 Hysteria2

1. 选择 `9`。
2. 填写服务器域名或公网 IP。
3. 填写 UDP 端口。
4. 填写证书域名。
5. 填写证书完整路径。
6. 填写私钥完整路径。
7. 设置密码。
8. 选择 IP 模式并保存。

证书需要提前准备好。例如：

```text
/etc/ssl/xray/fullchain.pem
/etc/ssl/xray/privkey.pem
```

脚本只读取你填写的证书，不会自动申请证书。使用 Hysteria2 时，要在云服务器安全组和系统防火墙放行对应的 UDP 端口。

## 六、查看节点和二维码

选择菜单 `5`，脚本会显示：

- VLESS 分享链接
- SS2022 分享链接
- Hysteria2 分享链接
- 终端二维码

在 v2rayN 等客户端中，可以直接复制分享链接导入。二维码只在当前终端显示，不会生成图片文件。

## 七、常用操作

### 重启

选择菜单 `3`，或执行：

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

选择菜单 `4`，或执行：

```bash
sh xray.sh --status
```

### 编辑配置

选择菜单 `7`，或执行：

```bash
sh xray.sh --edit
```

编辑完成后按编辑器提示保存并退出。脚本会检查配置，检查失败时不会替换原配置。

### 删除节点

选择菜单 `8`，然后选择要删除的协议。删除一个协议不会影响其他协议。

也可以直接删除：

```bash
sh xray.sh --remove-vless
sh xray.sh --remove-ss
sh xray.sh --remove-hy2
```

### 直接进入配置

```bash
sh xray.sh --vless
sh xray.sh --ss
sh xray.sh --hy2
```

## 八、文件位置

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

## 九、卸载

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

## 十、开机启动

配置完成并重启后，Xray 会加入系统开机启动。服务器重启后会自动运行。

## 十一、更新脚本

重新下载即可：

```bash
curl -fsSL https://raw.githubusercontent.com/GithubPlusMaxPro/xray_install/main/xray.sh -o xray.sh
chmod +x xray.sh
```

## 十二、端口检查

如果客户端无法连接，请检查：

1. 域名是否解析到服务器公网 IP。
2. 云服务器安全组是否放行端口。
3. 系统防火墙是否放行端口。
4. Hysteria2 是否放行了 UDP，而不是只放行 TCP。
5. 节点中的地址、端口、密码和证书域名是否填写正确。

项目地址：<https://github.com/GithubPlusMaxPro/xray_install>
