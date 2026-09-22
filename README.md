# Xray 交互式安装与管理脚本

支持 Debian/Ubuntu 和 Alpine，使用 Xray 创建和管理：

- VLESS + REALITY + XTLS Vision
- Shadowsocks 2022
- IPv4、IPv6、双栈 IPv6 优先

## 运行

```bash
curl -fsSL https://raw.githubusercontent.com/GithubPlusMaxPro/xray_install/main/xray.sh | sh
```

运行后会出现菜单：

```text
1) 配置/修改 VLESS Reality
2) 配置/修改 Shadowsocks 2022
3) 重启 Xray
4) 查看状态
5) 查看节点和配置摘要
6) 卸载 Xray（配置先备份）
0) 退出
```

首次选择协议后，脚本会询问该协议所需参数。再次选择同一协议时，会读取原参数作为默认值，可以修改端口、域名、加密方式和 IP 模式。

脚本启动时不会自动创建 VLESS 或 SS2022。只有在菜单中选择对应项目并确认保存后，才会写入该入站；另一种协议不会被自动添加。

配置成功后会询问是否立即重启，也可以随时从菜单选择“重启 Xray”。

配置成功后，终端会显示 v2rayN 可导入的分享字符串，并尝试直接显示终端二维码，不写入二维码图片或字符串文件。

菜单中的“查看节点和配置摘要”也会重新显示字符串和二维码。

## 直接操作

```bash
sh xray.sh                 # 交互菜单
sh xray.sh --vless         # 直接配置/修改 VLESS Reality
sh xray.sh --ss            # 直接配置/修改 SS2022
sh xray.sh --restart       # 重启 Xray
sh xray.sh --status        # 查看状态
sh xray.sh --uninstall     # 交互确认后卸载
sh xray.sh --uninstall --yes  # 无交互确认卸载
```

## 文件位置

```text
/usr/local/etc/xray/config.json   Xray 配置
/root/xray-nodes.json             节点参数和客户端信息
/var/log/xray/access.log          访问日志
/var/log/xray/error.log           错误日志
```

旧配置每次修改前都会备份为：

```text
/usr/local/etc/xray/config.json.bak.时间戳
```

卸载时不会直接删除配置、节点信息和日志，而是移动到：

```text
/root/xray-uninstall-backup-时间戳/
```

卸载不会删除系统通用依赖，例如 `curl`、`openssl` 和 `jq`。

脚本不会自动修改云防火墙、iptables、nftables 或 UFW 规则，请自行放行 VLESS 和 SS2022 端口。
