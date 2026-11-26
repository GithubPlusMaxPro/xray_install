#!/bin/sh
# Interactive Xray manager for VLESS REALITY, VLESS XHTTP, Shadowsocks 2022 and Hysteria2.
# Supports Debian/Ubuntu (systemd) and Alpine (OpenRC).

set -eu

XRAY_BIN=${XRAY_BIN:-/usr/local/bin/xray}
XRAY_DIR=${XRAY_DIR:-/usr/local/etc/xray}
CONFIG_FILE=${CONFIG_FILE:-$XRAY_DIR/config.json}
NODES_FILE=${NODES_FILE:-/root/xray-nodes.json}
ACTION=
REMOVE_PROTO=
ASSUME_YES=0
PURGE_DATA=0

die() {
    echo "错误: $*" >&2
    exit 1
}

info() {
    echo "==> $*"
}

usage() {
    cat <<'EOF'
用法:
  sh xray.sh                 打开交互管理菜单
  sh xray.sh --vless         直接配置/修改 VLESS Reality
  sh xray.sh --ss            直接配置/修改 Shadowsocks 2022
  sh xray.sh --hy2           直接配置/修改 Hysteria2
  sh xray.sh --xhttp         直接配置/修改 VLESS XHTTP
  sh xray.sh --warp          配置 SOCKS5 / WARP 出口路由
  sh xray.sh --edit          编辑并检查 Xray 配置文件
  sh xray.sh --remove        交互选择并删除 VLESS、SS2022、Hysteria2 或 XHTTP
  sh xray.sh --remove-vless  删除 VLESS Reality 入站
  sh xray.sh --remove-ss     删除 Shadowsocks 2022 入站
  sh xray.sh --remove-hy2    删除 Hysteria2 入站
  sh xray.sh --remove-xhttp  删除 VLESS XHTTP 入站
  sh xray.sh --restart       重启 Xray
  sh xray.sh --status        查看 Xray 状态
  sh xray.sh --uninstall     停止并卸载 Xray（会先备份）
  sh xray.sh --uninstall --yes  无交互确认卸载
  sh xray.sh --uninstall --purge --yes  无交互卸载并清空配置/日志

首次运行会安装 Xray，并创建基础配置。脚本不会自动修改防火墙规则。
EOF
}

require_root() {
    [ "$(id -u)" -eq 0 ] || die "请用 root 运行。"
}

detect_os() {
    [ -r /etc/os-release ] || die "找不到 /etc/os-release。"
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID:-}" in
        alpine) OS=alpine ;;
        debian|ubuntu) OS=debian ;;
        *) die "只支持 Debian/Ubuntu 和 Alpine，检测到: ${ID:-unknown}" ;;
    esac
    info "检测到系统: ${PRETTY_NAME:-$ID}（${OS} 服务管理）"
}

install_dependencies() {
    missing_dependencies=
    for required_command in curl tar openssl jq ip; do
        if ! command -v "$required_command" >/dev/null 2>&1; then
            if [ -n "$missing_dependencies" ]; then
                missing_dependencies="$missing_dependencies, $required_command"
            else
                missing_dependencies=$required_command
            fi
        fi
    done

    if [ -n "$missing_dependencies" ]; then
        info "缺少依赖: $missing_dependencies"
        info "开始安装系统依赖，请稍候..."
        if [ "$OS" = alpine ]; then
            info "使用 apk 安装 curl、tar、openssl、ca-certificates、jq 和 iproute2"
            apk add --no-cache curl tar openssl ca-certificates jq iproute2 >/dev/null
        else
            export DEBIAN_FRONTEND=noninteractive
            info "使用 apt 更新软件包索引"
            apt-get update -qq
            info "使用 apt 安装 curl、tar、openssl、ca-certificates、jq 和 iproute2"
            apt-get install -y -qq curl tar openssl ca-certificates jq iproute2 >/dev/null
        fi
    else
        info "系统依赖已存在，跳过软件包安装"
    fi

    if ! command -v qrencode >/dev/null 2>&1; then
        info "尝试安装终端二维码工具 qrencode（可选）"
        if [ "$OS" = alpine ]; then
            if ! apk add --no-cache libqrencode-tools >/dev/null 2>&1; then
                info "无法安装 libqrencode-tools；请确认 Alpine community 仓库已启用。"
            fi
        else
            export DEBIAN_FRONTEND=noninteractive
            if [ -z "$missing_dependencies" ] && ! apt-get update -qq; then
                info "无法更新 apt 软件包索引，跳过二维码工具安装。"
            elif ! apt-get install -y -qq qrencode >/dev/null; then
                info "无法安装 qrencode；分享链接仍可正常显示。"
            fi
        fi
    fi
    info "系统依赖已准备完成"
}

install_xray() {
    if [ -x "$XRAY_BIN" ]; then
        info "已找到 Xray 内核: $XRAY_BIN，跳过下载"
        return
    fi

    temp_dir=$(mktemp -d)
    trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM
    if [ "$OS" = alpine ]; then
        info "安装 Xray Alpine/OpenRC 版本"
        info "正在从 GitHub 下载 Xray 安装程序..."
        curl -fL --retry 3 --progress-bar \
            https://github.com/XTLS/Xray-install/raw/main/alpinelinux/install-release.sh \
            -o "$temp_dir/install-release.sh"
        info "正在执行 Xray Alpine 安装程序..."
        sh "$temp_dir/install-release.sh"
    else
        info "安装 Xray systemd 版本"
        info "正在从 GitHub 下载 Xray 安装程序..."
        curl -fL --retry 3 --progress-bar \
            https://github.com/XTLS/Xray-install/raw/main/install-release.sh \
            -o "$temp_dir/install-release.sh"
        info "正在执行 Xray Debian/Ubuntu 安装程序..."
        bash "$temp_dir/install-release.sh" install
    fi
    [ -x "$XRAY_BIN" ] || die "Xray 安装失败，找不到 $XRAY_BIN"
    info "Xray 内核安装完成: $XRAY_BIN"
}

ensure_base_files() {
    info "检查 Xray 配置和节点信息文件"
    mkdir -p "$XRAY_DIR"
    if [ ! -f "$CONFIG_FILE" ]; then
        info "创建基础配置: $CONFIG_FILE"
        cat > "$CONFIG_FILE" <<'EOF'
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {"domainStrategy": "UseIPv6v4"}
    },
    {"tag": "block", "protocol": "blackhole"}
  ]
}
EOF
        chmod 644 "$CONFIG_FILE"
    fi
    jq empty "$CONFIG_FILE" >/dev/null 2>&1 || die "现有 Xray 配置不是有效 JSON: $CONFIG_FILE"

    if [ ! -f "$NODES_FILE" ]; then
        info "创建节点信息文件: $NODES_FILE"
        printf '%s\n' '{}' > "$NODES_FILE"
        chmod 600 "$NODES_FILE"
    fi
    jq empty "$NODES_FILE" >/dev/null 2>&1 || die "节点信息文件不是有效 JSON: $NODES_FILE"
    info "基础文件检查完成"
}

get_node_field() {
    proto=$1
    key=$2
    jq -r --arg proto "$proto" --arg key "$key" '.[$proto][$key] // empty' "$NODES_FILE"
}

get_domain_strategy() {
    jq -r 'first(.outbounds[]? | select(.protocol == "freedom") | (.streamSettings.sockopt.domainStrategy // .settings.domainStrategy)) // "AsIs"' "$CONFIG_FILE"
}

get_warp_field() {
    field=$1
    jq -r --arg field "$field" \
        'first(.outbounds[]? | select(.tag == "warp" and .protocol == "socks") | .settings.servers[0][$field]) // empty' \
        "$CONFIG_FILE"
}

get_warp_user() {
    jq -r 'first(.outbounds[]? | select(.tag == "warp" and .protocol == "socks") | .settings.servers[0].users[0].user) // empty' "$CONFIG_FILE"
}

get_warp_pass() {
    jq -r 'first(.outbounds[]? | select(.tag == "warp" and .protocol == "socks") | .settings.servers[0].users[0].pass) // empty' "$CONFIG_FILE"
}

get_warp_route_summary() {
    jq -r '
      (first(.outbounds[]? | select(.tag == "warp" and .protocol == "socks") | .settings.servers[0]) // null) as $srv |
      if $srv == null then
        "未启用"
      else
        ([.routing.rules[]? | select(.outboundTag == "warp")] |
          if length == 0 then "已添加出站（\($srv.address):\($srv.port)），未配置路由规则"
          elif any(.[]; (.network // "") != "" and ((.domain // []) | length == 0)) then "全局走 warp（\($srv.address):\($srv.port)）"
          else "按域名分流走 warp（\($srv.address):\($srv.port)）: " + ([.[] | .domain[]?] | join(","))
          end)
      end
    ' "$CONFIG_FILE"
}

get_warp_route_domains() {
    jq -r '[.routing.rules[]? | select(.outboundTag == "warp") | .domain[]?] | join(",")' "$CONFIG_FILE"
}

get_vless_field() {
    field=$1
    jq -r --arg field "$field" \
        'first(.inbounds[]? | select(.tag == "vless-reality-in" or .tag == "vless-in") | .[$field]) // empty' \
        "$CONFIG_FILE"
}

get_vless_reality_field() {
    field=$1
    jq -r --arg field "$field" \
        'first(.inbounds[]? | select(.tag == "vless-reality-in" or .tag == "vless-in") | .streamSettings.realitySettings[$field]) // empty' \
        "$CONFIG_FILE"
}

get_vless_server_name() {
    jq -r 'first(.inbounds[]? | select(.tag == "vless-reality-in" or .tag == "vless-in") | (.streamSettings.realitySettings.serverNames[0] // .streamSettings.realitySettings.serverName)) // empty' "$CONFIG_FILE"
}

get_vless_uuid() {
    jq -r 'first(.inbounds[]? | select(.tag == "vless-reality-in" or .tag == "vless-in") | .settings.clients[0].id) // empty' "$CONFIG_FILE"
}

get_vless_flow() {
    jq -r 'first(.inbounds[]? | select(.tag == "vless-reality-in" or .tag == "vless-in") | .settings.clients[0].flow) // empty' "$CONFIG_FILE"
}

get_ss_field() {
    field=$1
    if [ "$field" = port ]; then
        jq -r 'first(.inbounds[]? | select(.tag == "ss2022-in") | .port) // empty' "$CONFIG_FILE"
    else
        jq -r --arg field "$field" \
            'first(.inbounds[]? | select(.tag == "ss2022-in") | .settings[$field]) // empty' \
            "$CONFIG_FILE"
    fi
}

get_hy2_field() {
    field=$1
    jq -r --arg field "$field" \
        'first(.inbounds[]? | select(.tag == "hysteria2-in" or .tag == "hy2-in") | .[$field]) // empty' \
        "$CONFIG_FILE"
}

get_hy2_tls_field() {
    field=$1
    jq -r --arg field "$field" \
        'first(.inbounds[]? | select(.tag == "hysteria2-in" or .tag == "hy2-in") | .streamSettings.tlsSettings[$field]) // empty' \
        "$CONFIG_FILE"
}

get_hy2_certificate_field() {
    field=$1
    jq -r --arg field "$field" \
        'first(.inbounds[]? | select(.tag == "hysteria2-in" or .tag == "hy2-in") | .streamSettings.tlsSettings.certificates[0][$field]) // empty' \
        "$CONFIG_FILE"
}

get_hy2_password() {
    jq -r 'first(.inbounds[]? | select(.tag == "hysteria2-in" or .tag == "hy2-in") | (.streamSettings.hysteriaSettings.auth // .settings.users[0].auth // .settings.clients[0].auth)) // empty' "$CONFIG_FILE"
}

get_xhttp_field() {
    field=$1
    jq -r --arg field "$field" \
        'first(.inbounds[]? | select(.tag == "vless-xhttp-in" or .tag == "xhttp-in") | .[$field]) // empty' \
        "$CONFIG_FILE"
}

get_xhttp_uuid() {
    jq -r 'first(.inbounds[]? | select(.tag == "vless-xhttp-in" or .tag == "xhttp-in") | .settings.clients[0].id) // empty' "$CONFIG_FILE"
}

get_xhttp_setting() {
    field=$1
    jq -r --arg field "$field" \
        'first(.inbounds[]? | select(.tag == "vless-xhttp-in" or .tag == "xhttp-in") | .streamSettings.xhttpSettings[$field]) // empty' \
        "$CONFIG_FILE"
}

get_xhttp_security() {
    jq -r 'first(.inbounds[]? | select(.tag == "vless-xhttp-in" or .tag == "xhttp-in") | .streamSettings.security) // empty' "$CONFIG_FILE"
}

get_xhttp_reality_field() {
    field=$1
    jq -r --arg field "$field" \
        'first(.inbounds[]? | select(.tag == "vless-xhttp-in" or .tag == "xhttp-in") | .streamSettings.realitySettings[$field]) // empty' \
        "$CONFIG_FILE"
}

get_xhttp_reality_sni() {
    jq -r 'first(.inbounds[]? | select(.tag == "vless-xhttp-in" or .tag == "xhttp-in") | (.streamSettings.realitySettings.serverNames[0] // .streamSettings.realitySettings.serverName)) // empty' "$CONFIG_FILE"
}

get_xhttp_reality_short_id() {
    jq -r 'first(.inbounds[]? | select(.tag == "vless-xhttp-in" or .tag == "xhttp-in") | .streamSettings.realitySettings.shortIds[0]) // empty' "$CONFIG_FILE"
}

get_xhttp_tls_field() {
    field=$1
    jq -r --arg field "$field" \
        'first(.inbounds[]? | select(.tag == "vless-xhttp-in" or .tag == "xhttp-in") | .streamSettings.tlsSettings[$field]) // empty' \
        "$CONFIG_FILE"
}

get_xhttp_certificate_field() {
    field=$1
    jq -r --arg field "$field" \
        'first(.inbounds[]? | select(.tag == "vless-xhttp-in" or .tag == "xhttp-in") | .streamSettings.tlsSettings.certificates[0][$field]) // empty' \
        "$CONFIG_FILE"
}

get_xhttp_extra() {
    jq -rc 'first(.inbounds[]? | select(.tag == "vless-xhttp-in" or .tag == "xhttp-in") | .streamSettings.xhttpSettings.extra) | if type == "object" and length > 0 then tojson else empty end' "$CONFIG_FILE"
}

get_xhttp_trusted_xff() {
    jq -r 'first(.inbounds[]? | select(.tag == "vless-xhttp-in" or .tag == "xhttp-in") | .streamSettings.sockopt.trustedXForwardedFor) | if type == "array" then join(",") elif type == "string" then . else empty end' "$CONFIG_FILE"
}

detect_server_address() {
    detected_address=
    if command -v ip >/dev/null 2>&1; then
        detected_address=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "src") {print $(i + 1); exit}}')
        if [ -z "$detected_address" ]; then
            detected_address=$(ip -6 route get 2606:4700:4700::1111 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "src") {print $(i + 1); exit}}')
        fi
        if [ -z "$detected_address" ]; then
            detected_address=$(ip -o -4 addr show scope global 2>/dev/null | awk '{sub(/\/.*$/, "", $4); print $4; exit}')
        fi
        if [ -z "$detected_address" ]; then
            detected_address=$(ip -o -6 addr show scope global 2>/dev/null | awk '{sub(/\/.*$/, "", $4); print $4; exit}')
        fi
    fi
    if [ -z "$detected_address" ] && command -v hostname >/dev/null 2>&1; then
        detected_address=$(hostname -I 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i !~ /^127\./ && $i != "::1") {print $i; exit}}')
    fi
    printf '%s' "$detected_address"
}

format_url_host() {
    host_value=$1
    case "$host_value" in
        \[*\]) printf '%s' "$host_value" ;;
        *:*) printf '[%s]' "$host_value" ;;
        *) printf '%s' "$host_value" ;;
    esac
}

make_ss_url() {
    server_address=$1
    ss_port_value=$2
    ss_method_value=$3
    ss_password_value=$4
    ss_host=$(format_url_host "$server_address")
    ss_userinfo=$(printf '%s' "$ss_method_value:$ss_password_value" | openssl base64 -A | tr '+/' '-_' | tr -d '=')
    SS_URL="ss://$ss_userinfo@$ss_host:$ss_port_value#ss2022"
}

urlencode() {
    printf '%s' "$1" | jq -sRr @uri
}

make_hy2_url() {
    hy2_host=$(format_url_host "$1")
    hy2_port_value=$2
    hy2_password_value=$3
    hy2_sni_value=$4
    hy2_mport_value=${5:-}
    hy2_password_encoded=$(urlencode "$hy2_password_value")
    hy2_sni_encoded=$(urlencode "$hy2_sni_value")
    hy2_query="sni=$hy2_sni_encoded&alpn=h3"
    if [ -n "$hy2_mport_value" ]; then
        hy2_query="$hy2_query&mport=$hy2_mport_value"
    fi
    HY2_URL="hysteria2://$hy2_password_encoded@$hy2_host:$hy2_port_value/?$hy2_query#hysteria2"
}

make_xhttp_url() {
    xhttp_host_addr=$(format_url_host "$1")
    xhttp_port_val=$2
    xhttp_uuid_val=$3
    xhttp_path_val=$4
    xhttp_mode_val=$5
    xhttp_sec_val=$6
    xhttp_sni_val=$7
    xhttp_pbk_val=$8
    xhttp_sid_val=$9
    shift 9
    xhttp_http_host=${1:-}
    xhttp_extra_val=${2:-}

    xhttp_path_enc=$(urlencode "$xhttp_path_val")
    xhttp_mode_enc=$(urlencode "$xhttp_mode_val")
    xhttp_query="encryption=none&type=xhttp&path=$xhttp_path_enc&mode=$xhttp_mode_enc"
    if [ -n "$xhttp_http_host" ]; then
        xhttp_http_host_enc=$(urlencode "$xhttp_http_host")
        xhttp_query="$xhttp_query&host=$xhttp_http_host_enc"
    fi

    case "$xhttp_sec_val" in
        reality)
            xhttp_sni_enc=$(urlencode "$xhttp_sni_val")
            xhttp_query="$xhttp_query&security=reality&sni=$xhttp_sni_enc&fp=chrome&pbk=$xhttp_pbk_val&sid=$xhttp_sid_val"
            ;;
        tls)
            xhttp_sni_enc=$(urlencode "$xhttp_sni_val")
            xhttp_query="$xhttp_query&security=tls&sni=$xhttp_sni_enc&fp=chrome"
            ;;
        *)
            xhttp_query="$xhttp_query&security=none"
            ;;
    esac
    if [ -n "$xhttp_extra_val" ] && [ "$xhttp_extra_val" != "{}" ]; then
        xhttp_extra_enc=$(urlencode "$xhttp_extra_val")
        xhttp_query="$xhttp_query&extra=$xhttp_extra_enc"
    fi
    XHTTP_URL="vless://$xhttp_uuid_val@$xhttp_host_addr:$xhttp_port_val?$xhttp_query#vless-xhttp"
}

show_terminal_qr() {
    node_name=$1
    node_payload=$2
    if command -v qrencode >/dev/null 2>&1; then
        echo "终端二维码 [$node_name]:"
        qrencode -t ANSIUTF8 "$node_payload" 2>/dev/null || qrencode -t UTF8 "$node_payload" 2>/dev/null || true
    else
        echo "未找到 qrencode，无法显示终端二维码。"
        echo "v2rayN 字符串仍已在上方显示。"
    fi
}

show_vless_node() {
    node_url=$(get_node_field vless url)
    [ -n "$node_url" ] || return 0
    echo
    echo '=== VLESS Reality 节点 ==='
    echo "$node_url"
    show_terminal_qr vless-reality "$node_url"
}

show_ss_node() {
    node_address=$(get_node_field ss2022 address)
    node_port=$(get_node_field ss2022 port)
    node_method=$(get_node_field ss2022 method)
    node_password=$(get_node_field ss2022 password)
    [ -n "$node_address" ] && [ -n "$node_port" ] && [ -n "$node_method" ] && [ -n "$node_password" ] || return 0
    make_ss_url "$node_address" "$node_port" "$node_method" "$node_password"
    echo
    echo '=== Shadowsocks 2022 节点 ==='
    echo "$SS_URL"
    echo "加密方式: $node_method"
    echo "密码: $node_password"
    show_terminal_qr ss2022 "$SS_URL"
}

show_hy2_node() {
    node_address=$(get_node_field hy2 address)
    node_port=$(get_node_field hy2 port)
    node_password=$(get_node_field hy2 password)
    node_sni=$(get_node_field hy2 sni)
    node_cert=$(get_node_field hy2 certificateFile)
    node_key=$(get_node_field hy2 keyFile)
    node_mport=$(get_node_field hy2 mport)
    [ -n "$node_address" ] && [ -n "$node_port" ] && [ -n "$node_password" ] && [ -n "$node_sni" ] || return 0
    make_hy2_url "$node_address" "$node_port" "$node_password" "$node_sni" "$node_mport"
    echo
    echo '=== Hysteria2 节点 ==='
    echo "$HY2_URL"
    echo "SNI: $node_sni"
    echo "证书: $node_cert"
    echo "私钥: $node_key"
    [ -z "$node_mport" ] || echo "端口跳跃: $node_mport"
    show_terminal_qr hysteria2 "$HY2_URL"
}

show_xhttp_node() {
    node_address=$(get_node_field xhttp address)
    node_port=$(get_node_field xhttp port)
    node_uuid=$(get_node_field xhttp uuid)
    node_path=$(get_node_field xhttp path)
    node_mode=$(get_node_field xhttp mode)
    node_security=$(get_node_field xhttp security)
    node_sni=$(get_node_field xhttp sni)
    node_pbk=$(get_node_field xhttp publicKey)
    node_sid=$(get_node_field xhttp shortId)
    node_host=$(get_node_field xhttp host)
    node_extra=$(get_xhttp_extra)
    node_xff=$(get_xhttp_trusted_xff)
    if [ -n "$node_address" ] && [ -n "$node_port" ] && [ -n "$node_uuid" ] && [ -n "$node_path" ]; then
        make_xhttp_url "$node_address" "$node_port" "$node_uuid" "$node_path" "${node_mode:-auto}" "${node_security:-none}" "$node_sni" "$node_pbk" "$node_sid" "$node_host" "$node_extra"
        node_url=$XHTTP_URL
    else
        node_url=$(get_node_field xhttp url)
    fi
    [ -n "$node_url" ] || return 0
    echo
    echo '=== VLESS XHTTP 节点 ==='
    echo "$node_url"
    echo "路径: $node_path"
    echo "模式: $node_mode"
    echo "传输安全: $node_security"
    [ -z "$node_host" ] || echo "Host: $node_host"
    [ -z "$node_xff" ] || echo "信任 XFF 头部: $node_xff"
    [ -z "$node_extra" ] || echo "Extra: $node_extra"
    show_terminal_qr vless-xhttp "$node_url"
}

get_vless_short_id() {
    jq -r 'first(.inbounds[]? | select(.tag == "vless-reality-in" or .tag == "vless-in") | .streamSettings.realitySettings.shortIds[0]) // empty' "$CONFIG_FILE"
}

is_port() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ "$1" -ge 1 ] 2>/dev/null && [ "$1" -le 65535 ] 2>/dev/null
}

is_valid_mport() {
    mport_val=$1
    [ -n "$mport_val" ] || return 1
    case "$mport_val" in
        ,*|*,,*|*,|*[![0-9,-]*) return 1 ;;
    esac
    saved_ifs=$IFS
    IFS=,
    # shellcheck disable=SC2086
    set -- $mport_val
    IFS=$saved_ifs
    for seg in "$@"; do
        case "$seg" in
            *-*)
                seg_start=${seg%%-*}
                seg_end=${seg#*-}
                case "$seg_end" in
                    *-*) return 1 ;;
                esac
                is_port "$seg_start" && is_port "$seg_end" && [ "$seg_start" -lt "$seg_end" ] || return 1
                ;;
            *)
                is_port "$seg" || return 1
                ;;
        esac
    done
    return 0
}

print_hy2_hopping_commands() {
    target_port=$1
    hop_mport=$2
    echo
    echo "=== Hysteria2 端口跳跃防火墙转发参考（脚本不会自动修改防火墙） ==="
    echo "请先在云服务器安全组与系统防火墙放行 UDP 端口: $hop_mport"
    echo "方式 1（nftables，推荐）:"
    echo "  nft add table inet hy2_hop"
    echo "  nft 'add chain inet hy2_hop prerouting { type nat hook prerouting priority dstnat; policy accept; }'"
    echo "  nft add rule inet hy2_hop prerouting udp dport { $hop_mport } redirect to :$target_port"
    echo "方式 2（iptables / ip6tables）:"
    saved_ifs=$IFS
    IFS=,
    # shellcheck disable=SC2086
    set -- $hop_mport
    IFS=$saved_ifs
    for seg in "$@"; do
        ipt_seg=$(printf '%s' "$seg" | tr '-' ':')
        echo "  iptables -t nat -A PREROUTING -p udp --dport $ipt_seg -j REDIRECT --to-ports $target_port"
        echo "  ip6tables -t nat -A PREROUTING -p udp --dport $ipt_seg -j REDIRECT --to-ports $target_port"
    done
}

is_safe_value() {
    case "$1" in
        *[![:alnum:].:_\[\]-]*) return 1 ;;
    esac
    return 0
}

is_valid_ipv4_literal() {
    ipv4_value=$1
    saved_ifs=$IFS
    IFS=.
    # This function is called only after the value has been limited to digits and dots.
    # shellcheck disable=SC2086
    set -- $ipv4_value
    IFS=$saved_ifs
    [ "$#" -eq 4 ] || return 1
    for octet in "$@"; do
        case "$octet" in
            ''|*[!0-9]*) return 1 ;;
        esac
        [ "$octet" -le 255 ] 2>/dev/null || return 1
    done
    return 0
}

validate_server_address() {
    server_address_value=$1
    [ -n "$server_address_value" ] || return 1
    [ "$server_address_value" != YOUR_SERVER_IP_OR_DOMAIN ] || return 1
    is_safe_value "$server_address_value" || return 1
    case "$server_address_value" in
        *[!0-9.]*) return 0 ;;
        *) is_valid_ipv4_literal "$server_address_value" ;;
    esac
}

prompt_input() {
    prompt_text=$1
    default_value=${2:-}
    answer=
    if [ -n "$default_value" ]; then
        printf '%s [%s]: ' "$prompt_text" "$default_value" > /dev/tty
    else
        printf '%s: ' "$prompt_text" > /dev/tty
    fi
    if ! IFS= read -r answer < /dev/tty; then
        die "无法从当前终端读取输入，请使用带 TTY 的 SSH 会话，并运行 sh xray.sh。"
    fi
    [ -n "$answer" ] || answer=$default_value
    printf '%s' "$answer"
}

yes_no() {
    prompt_text=$1
    default_value=$2
    if [ "$default_value" = yes ]; then
        suffix='Y/n'
    else
        suffix='y/N'
    fi
    printf '%s [%s]: ' "$prompt_text" "$suffix" > /dev/tty
    answer=
    if IFS= read -r answer < /dev/tty; then
        :
    else
        answer=
    fi
    answer=$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')
    case "$answer" in
        y|yes) return 0 ;;
        n|no) return 1 ;;
        '') [ "$default_value" = yes ] && return 0 || return 1 ;;
        *) die "请输入 y 或 n。" ;;
    esac
}

derive_server_name() {
    target=$1
    case "$target" in
        \[*\]:*) name=${target#\[}; name=${name%%\]*} ;;
        *:*) name=${target%:*} ;;
        *) name=$target ;;
    esac
    printf '%s' "$name"
}

normalize_target() {
    case "$1" in
        *:*) printf '%s' "$1" ;;
        *) printf '%s:443' "$1" ;;
    esac
}

choose_outbound_mode() {
    default_mode=$1
    case "$default_mode" in
        dual|UseIPv6v4) default_choice=1 ;;
        ipv4|UseIPv4) default_choice=2 ;;
        ipv6|UseIPv6) default_choice=3 ;;
        AsIs|'') default_choice=4 ;;
        *) default_choice=4 ;;
    esac
    printf '%s\n' \
        '出站域名解析模式:' \
        '  1) UseIPv6v4  IPv6 优先，IPv4 回落' \
        '  2) UseIPv4    使用 IPv4 解析结果' \
        '  3) UseIPv6    使用 IPv6 解析结果' \
        '  4) AsIs       使用 Xray 默认解析方式' > /dev/tty
    choice=$(prompt_input '请选择' "$default_choice")
    case "$choice" in
        4|AsIs) DOMAIN_STRATEGY=AsIs ;;
        1|UseIPv6v4) DOMAIN_STRATEGY=UseIPv6v4 ;;
        2|UseIPv4) DOMAIN_STRATEGY=UseIPv4 ;;
        3|UseIPv6) DOMAIN_STRATEGY=UseIPv6 ;;
        *) die "出站模式选择无效，请输入 1、2、3 或 4。" ;;
    esac
}

configure_outbound_mode() {
    old_mode=$(get_domain_strategy)
    [ -n "$old_mode" ] || old_mode=AsIs

    echo
    echo '=== 设置所有 Freedom 直连出站的 IP 模式 ==='
    choose_outbound_mode "$old_mode"
    tmp_config="$CONFIG_FILE.outbound-mode.$$.json"

    jq --arg strategy "$DOMAIN_STRATEGY" \
       '.outbounds = (if any(.outbounds[]?; .protocol == "freedom") then
           (.outbounds | map(if .protocol == "freedom" then
             .settings = ((.settings // {}) + {domainStrategy: $strategy})
             | .streamSettings = ((.streamSettings // {}) + {sockopt: ((.streamSettings.sockopt // {}) + {domainStrategy: $strategy})})
           else . end))
         else
           ((.outbounds // []) + [{tag: "direct", protocol: "freedom", settings: {domainStrategy: $strategy}, streamSettings: {sockopt: {domainStrategy: $strategy}}}])
         end)' "$CONFIG_FILE" > "$tmp_config" || {
        rm -f "$tmp_config"
        die '生成出站模式配置失败。'
    }

    info "检查 Xray 配置"
    if ! "$XRAY_BIN" run -test -format json -config "$tmp_config"; then
        rm -f "$tmp_config"
        die '配置检查失败，出站模式未修改。'
    fi
    mv "$tmp_config" "$CONFIG_FILE"
    chmod 644 "$CONFIG_FILE"
    echo "所有 Freedom 直连出站的域名解析模式已设为: $DOMAIN_STRATEGY"
    if yes_no '现在重启 Xray 使配置生效' yes; then
        restart_xray
    fi
}

choose_ss_method() {
    default_method=$1
    case "$default_method" in
        2022-blake3-aes-128-gcm) default_choice=1 ;;
        2022-blake3-chacha20-poly1305) default_choice=3 ;;
        *) default_choice=2 ;;
    esac
    printf '%s\n' \
        'SS2022 加密方式:' \
        '  1) 2022-blake3-aes-128-gcm' \
        '  2) 2022-blake3-aes-256-gcm（推荐）' \
        '  3) 2022-blake3-chacha20-poly1305' > /dev/tty
    choice=$(prompt_input '请选择' "$default_choice")
    case "$choice" in
        1|2022-blake3-aes-128-gcm) SS_METHOD=2022-blake3-aes-128-gcm ;;
        2|2022-blake3-aes-256-gcm) SS_METHOD=2022-blake3-aes-256-gcm ;;
        3|2022-blake3-chacha20-poly1305) SS_METHOD=2022-blake3-chacha20-poly1305 ;;
        *) die "SS2022 加密方式选择无效。" ;;
    esac
}

generate_uuid() {
    cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || openssl rand -hex 16 | awk '{printf "%s-%s-%s-%s-%s\n", substr($0,1,8),substr($0,9,4),substr($0,13,4),substr($0,17,4),substr($0,21,12)}'
}

generate_reality_keys() {
    key_output=$($XRAY_BIN x25519 2>/dev/null) || die "无法生成 Reality 密钥。"
    REALITY_PRIVATE_KEY=$(printf '%s\n' "$key_output" | awk -F': *' 'tolower($1) ~ /private/ {print $2; exit}')
    REALITY_PUBLIC_KEY=$(printf '%s\n' "$key_output" | awk -F': *' 'tolower($1) ~ /password|public/ {print $2; exit}')
    [ -n "$REALITY_PRIVATE_KEY" ] || die "无法解析 Reality private key。"
    [ -n "$REALITY_PUBLIC_KEY" ] || die "无法解析 Reality public key。"
}

derive_reality_public_key() {
    key_output=$($XRAY_BIN x25519 -i "$REALITY_PRIVATE_KEY" 2>/dev/null) || die "无法从现有 private key 生成 public key。"
    REALITY_PUBLIC_KEY=$(printf '%s\n' "$key_output" | awk -F': *' 'tolower($1) ~ /password|public/ {print $2; exit}')
    [ -n "$REALITY_PUBLIC_KEY" ] || die "无法解析 Reality public key。"
}

warn_cert_permissions() {
    cert_path=$1
    if command -v ls >/dev/null 2>&1; then
        perms=$(ls -ldL "$cert_path" 2>/dev/null | awk '{print $1}')
        case "$perms" in
            ????????r?) : ;;
            *) info "提示: $cert_path 当前对非 root 用户不可读（$perms）；若 Xray 以 nobody 等非 root 用户运行，请确保服务用户有读取权限。" ;;
        esac
    fi
}

ss_method_key_bytes() {
    case "$1" in
        2022-blake3-aes-128-gcm) printf '16' ;;
        *) printf '32' ;;
    esac
}

normalize_xhttp_path() {
    case "$1" in
        /*) printf '%s' "$1" ;;
        *) printf '/%s' "$1" ;;
    esac
}

is_safe_xhttp_path() {
    case "$1" in
        ''|/*[![:alnum:]/._~-]*) return 1 ;;
        /*) return 0 ;;
        *) return 1 ;;
    esac
}

choose_xhttp_mode() {
    default_mode=$1
    case "$default_mode" in
        packet-up) default_choice=2 ;;
        stream-up) default_choice=3 ;;
        stream-one) default_choice=4 ;;
        *) default_choice=1 ;;
    esac
    printf '%s\n' \
        'XHTTP 传输模式:' \
        '  1) auto        自动协商（推荐）' \
        '  2) packet-up   分包上行，CDN/反代兼容性最好' \
        '  3) stream-up   流式上行，上下行分离' \
        '  4) stream-one  单连接双向流' > /dev/tty
    choice=$(prompt_input '请选择' "$default_choice")
    case "$choice" in
        1|auto) XHTTP_MODE=auto ;;
        2|packet-up) XHTTP_MODE=packet-up ;;
        3|stream-up) XHTTP_MODE=stream-up ;;
        4|stream-one) XHTTP_MODE=stream-one ;;
        *) die "XHTTP 模式选择无效，请输入 1、2、3 或 4。" ;;
    esac
}

choose_xhttp_security() {
    default_sec=$1
    case "$default_sec" in
        tls) default_choice=2 ;;
        none) default_choice=3 ;;
        *) default_choice=1 ;;
    esac
    printf '%s\n' \
        'XHTTP 传输安全:' \
        '  1) reality  无需证书，直连推荐' \
        '  2) tls      使用已有 TLS 证书' \
        '  3) none     无 TLS（仅配合 Nginx/Caddy/CDN 反代）' > /dev/tty
    choice=$(prompt_input '请选择' "$default_choice")
    case "$choice" in
        1|reality) XHTTP_SECURITY=reality ;;
        2|tls) XHTTP_SECURITY=tls ;;
        3|none) XHTTP_SECURITY=none ;;
        *) die "XHTTP 传输安全选择无效，请输入 1、2 或 3。" ;;
    esac
}

is_safe_xff_list() {
    case "$1" in
        *[![:alnum:],_-]*) return 1 ;;
    esac
    return 0
}

choose_xhttp_xff() {
    default_xff=$1
    case "$default_xff" in
        '') default_choice=0 ;;
        CF-Connecting-IP) default_choice=1 ;;
        X-Forwarded-For) default_choice=2 ;;
        *) default_choice=$default_xff ;;
    esac
    printf '%s\n' \
        '信任的 XFF 头部（仅 CDN/反代获取真实 IP 时需要，直连请选 0）:' \
        '  0) 不设置（默认）' \
        '  1) CF-Connecting-IP  Cloudflare CDN' \
        '  2) X-Forwarded-For   Nginx / Caddy 等反代' \
        '  也可直接输入自定义头部名（多个用逗号分隔）' > /dev/tty
    choice=$(prompt_input '请选择或输入头部名' "$default_choice")
    case "$choice" in
        ''|0|none) XHTTP_XFF= ;;
        1) XHTTP_XFF=CF-Connecting-IP ;;
        2) XHTTP_XFF=X-Forwarded-For ;;
        *)
            cleaned_xff=$(printf '%s' "$choice" | tr -d '[:space:]')
            is_safe_xff_list "$cleaned_xff" || die "XFF 头部名称包含不支持的字符（仅支持字母、数字、-、_ 和逗号）。"
            XHTTP_XFF=$cleaned_xff
            ;;
    esac
}

save_node() {
    proto=$1
    node_json=$2
    nodes_tmp="$NODES_FILE.new.$$"
    jq --arg proto "$proto" --argjson node "$node_json" '.[$proto] = $node' "$NODES_FILE" > "$nodes_tmp"
    mv "$nodes_tmp" "$NODES_FILE"
    chmod 600 "$NODES_FILE"
}

write_config() {
    inbound_json=$1
    remove_tag_one=$2
    remove_tag_two=$3
    tmp_config="$CONFIG_FILE.new.$$.json"

    jq --argjson inbound "$inbound_json" \
       --arg remove_one "$remove_tag_one" \
       --arg remove_two "$remove_tag_two" \
       '.log = ((.log // {}) + {
          loglevel: (.log.loglevel // "warning"),
          access: (.log.access // "/var/log/xray/access.log"),
          error: (.log.error // "/var/log/xray/error.log")
        })
        | .inbounds = ((.inbounds // []) | map(select((.tag // "") != $remove_one and (.tag // "") != $remove_two)) + [$inbound])
        | .outbounds = (if any(.outbounds[]?; .protocol == "freedom") then
            .outbounds
          else
            ((.outbounds // []) + [{tag: "direct", protocol: "freedom", settings: {}}])
          end)' "$CONFIG_FILE" > "$tmp_config"

    info "检查 Xray 配置"
    if ! "$XRAY_BIN" run -test -format json -config "$tmp_config"; then
        rm -f "$tmp_config"
        die "配置检查失败，正式配置未修改。"
    fi
    mv "$tmp_config" "$CONFIG_FILE"
    chmod 644 "$CONFIG_FILE"
    echo "配置已保存: $CONFIG_FILE"
}

restart_xray() {
    info "启用 Xray 开机自启并重启服务"
    if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
        systemctl daemon-reload
        systemctl enable xray >/dev/null 2>&1 || true
        systemctl restart xray
    elif command -v rc-service >/dev/null 2>&1; then
        rc-update add xray default >/dev/null 2>&1 || true
        rc-service xray restart
    else
        die "找不到 systemd 或 OpenRC。"
    fi
    echo "Xray 已重启，开机自启已启用。"
}

edit_config() {
    edit_tmp="$CONFIG_FILE.edit.$$.json"
    cp "$CONFIG_FILE" "$edit_tmp"

    editor=${EDITOR:-}
    if [ -z "$editor" ] || ! command -v "$editor" >/dev/null 2>&1; then
        editor=
        for candidate in vim nvim vi nano; do
            if command -v "$candidate" >/dev/null 2>&1; then
                editor=$candidate
                break
            fi
        done
    fi
    [ -n "$editor" ] || {
        rm -f "$edit_tmp"
        die "找不到编辑器，请先安装 vi、vim 或 nano。"
    }

    info "正在编辑临时配置: $edit_tmp"
    # Ensure a clean terminal before and after the full-screen editor.
    stty sane </dev/tty >/dev/tty 2>/dev/null || true
    case "$editor" in
        *vim*|*nvim*)
            if ! "$editor" -N -n -u NONE -U NONE -i NONE "$edit_tmp" </dev/tty >/dev/tty; then
                rm -f "$edit_tmp"
                stty sane </dev/tty >/dev/tty 2>/dev/null || true
                die "编辑器退出失败，正式配置未修改。"
            fi
            ;;
        *)
            if ! "$editor" "$edit_tmp" </dev/tty >/dev/tty; then
                rm -f "$edit_tmp"
                stty sane </dev/tty >/dev/tty 2>/dev/null || true
                die "编辑器退出失败，正式配置未修改。"
            fi
            ;;
    esac
    stty sane </dev/tty >/dev/tty 2>/dev/null || true
    if [ ! -f "$edit_tmp" ]; then
        rm -f "$edit_tmp"
        die "编辑器未生成配置文件，正式配置未修改。"
    fi

    info "检查编辑后的 Xray 配置"
    if ! "$XRAY_BIN" run -test -format json -config "$edit_tmp"; then
        rm -f "$edit_tmp"
        die "配置检查失败，正式配置未修改。"
    fi

    mv "$edit_tmp" "$CONFIG_FILE"
    chmod 644 "$CONFIG_FILE"
    echo "配置已保存: $CONFIG_FILE"
    if yes_no '现在重启 Xray 使配置生效' yes; then
        restart_xray
    fi
    echo '编辑完成，已返回管理菜单；输入 0 退出。'
}

remove_protocol() {
    remove_choice=$REMOVE_PROTO
    if [ -z "$remove_choice" ]; then
        printf '%s\n' \
            '删除协议:' \
            '  1) VLESS Reality' \
            '  2) Shadowsocks 2022' \
            '  3) Hysteria2' \
            '  4) VLESS XHTTP' \
            '  0) 取消' > /dev/tty
        remove_choice=$(prompt_input '请选择' '')
        case "$remove_choice" in
            1|vless) remove_choice=vless ;;
            2|ss|ss2022) remove_choice=ss2022 ;;
            3|hy2|hysteria2) remove_choice=hy2 ;;
            4|xhttp) remove_choice=xhttp ;;
            0|q|Q) echo '已取消删除。'; return 0 ;;
            *) die '删除选项无效，请输入 1、2、3、4 或 0。' ;;
        esac
    fi

    case "$remove_choice" in
        vless)
            remove_one=vless-reality-in
            remove_two=vless-in
            remove_title='VLESS Reality'
            ;;
        ss2022)
            remove_one=ss2022-in
            remove_two=
            remove_title='Shadowsocks 2022'
            ;;
        hy2)
            remove_one=hysteria2-in
            remove_two=hy2-in
            remove_title='Hysteria2'
            ;;
        xhttp)
            remove_one=vless-xhttp-in
            remove_two=xhttp-in
            remove_title='VLESS XHTTP'
            ;;
        *) die "不支持的删除协议: $remove_choice" ;;
    esac

    yes_no "确认删除 $remove_title？配置和节点信息都会删除" no || {
        echo '已取消删除。'
        return 0
    }

    remove_config_tmp="$CONFIG_FILE.remove.$$.json"
    remove_nodes_tmp="$NODES_FILE.remove.$$.json"
    jq --arg remove_one "$remove_one" --arg remove_two "$remove_two" \
        '.inbounds = ((.inbounds // []) | map(select((.tag // "") != $remove_one and ($remove_two == "" or (.tag // "") != $remove_two))))' \
        "$CONFIG_FILE" > "$remove_config_tmp" || {
        rm -f "$remove_config_tmp"
        die '生成删除后的 Xray 配置失败。'
    }
    jq --arg proto "$remove_choice" 'del(.[$proto])' "$NODES_FILE" > "$remove_nodes_tmp" || {
        rm -f "$remove_config_tmp" "$remove_nodes_tmp"
        die '生成删除后的节点信息失败。'
    }

    info "检查删除后的 Xray 配置"
    if ! "$XRAY_BIN" run -test -format json -config "$remove_config_tmp"; then
        rm -f "$remove_config_tmp" "$remove_nodes_tmp"
        die '配置检查失败，未删除任何内容。'
    fi

    mv "$remove_config_tmp" "$CONFIG_FILE"
    chmod 644 "$CONFIG_FILE"
    mv "$remove_nodes_tmp" "$NODES_FILE"
    chmod 600 "$NODES_FILE"
    echo "$remove_title 已删除。"
    if yes_no '现在重启 Xray 使配置生效' yes; then
        restart_xray
    fi
}

stop_xray() {
    if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
        systemctl disable --now xray >/dev/null 2>&1 || true
    elif command -v rc-service >/dev/null 2>&1; then
        rc-service xray stop >/dev/null 2>&1 || true
        rc-update del xray default >/dev/null 2>&1 || true
    fi
}

move_to_backup() {
    source_path=$1
    [ -e "$source_path" ] || return 0
    backup_name=$(printf '%s' "$source_path" | sed 's#^/##; s#/#_#g')
    mv "$source_path" "$UNINSTALL_BACKUP/$backup_name"
}

remove_data() {
    source_path=$1
    [ -e "$source_path" ] || return 0
    rm -rf "$source_path"
}

uninstall_xray() {
    if [ "$ASSUME_YES" -ne 1 ]; then
        yes_no '确定卸载 Xray？配置、日志和节点信息会移动到备份目录' no || {
            echo '已取消卸载。'
            return
        }
        if [ "$PURGE_DATA" -eq 1 ]; then
            yes_no '确认永久清空配置、节点信息和日志？此操作不可恢复' no || {
                echo '已取消清空，未执行卸载。'
                return
            }
        else
            if yes_no '是否清空配置、节点信息和日志？默认保留备份' no; then
                PURGE_DATA=1
            fi
        fi
    fi

    stop_xray

    if [ "$PURGE_DATA" -eq 1 ]; then
        remove_data "$XRAY_BIN"
        remove_data "$XRAY_DIR"
        remove_data /usr/local/share/xray
        remove_data /var/log/xray
        remove_data "$NODES_FILE"
        remove_data /etc/systemd/system/xray.service
        remove_data /etc/systemd/system/xray@.service
        remove_data /etc/systemd/system/xray.service.d
        remove_data /etc/init.d/xray
    else
        UNINSTALL_BACKUP=/root/xray-uninstall-backup-$(date +%Y%m%d%H%M%S)
        mkdir -p "$UNINSTALL_BACKUP"
        chmod 700 "$UNINSTALL_BACKUP"
        move_to_backup "$XRAY_BIN"
        move_to_backup "$XRAY_DIR"
        move_to_backup /usr/local/share/xray
        move_to_backup /var/log/xray
        move_to_backup "$NODES_FILE"
        move_to_backup /etc/systemd/system/xray.service
        move_to_backup /etc/systemd/system/xray@.service
        move_to_backup /etc/systemd/system/xray.service.d
        move_to_backup /etc/init.d/xray
    fi

    if command -v systemctl >/dev/null 2>&1; then
        systemctl daemon-reload >/dev/null 2>&1 || true
    fi
    echo "Xray 已停止并卸载。"
    if [ "$PURGE_DATA" -eq 1 ]; then
        echo "配置、节点信息和日志已清空，无法恢复。"
    else
        echo "备份目录: $UNINSTALL_BACKUP"
    fi
    echo "系统依赖（curl、openssl、jq 等）未删除。"
    exit 0
}

show_status() {
    if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
        systemctl --no-pager --full status xray || true
    elif command -v rc-service >/dev/null 2>&1; then
        rc-service xray status || true
    fi
}

show_summary() {
    echo
    echo '=== Xray 入站 ==='
    jq -r '.inbounds[]? | "tag=\(.tag // "-") protocol=\(.protocol // "-") listen=\(.listen // "-") port=\(.port // "-")"' "$CONFIG_FILE"
    echo
    echo "出站 IP 策略: $(get_domain_strategy)"
    echo "SOCKS5 / WARP 出口: $(get_warp_route_summary)"
    echo "配置文件: $CONFIG_FILE"
    echo "节点参数: $NODES_FILE"
    show_vless_node
    show_ss_node
    show_hy2_node
    show_xhttp_node
    echo
}

configure_vless() {
    old_port=$(get_vless_field port)
    old_listen=$(get_vless_field listen)
    old_uuid=$(get_vless_uuid)
    old_flow=$(get_vless_flow)
    old_target=$(get_vless_reality_field target)
    [ -n "$old_target" ] || old_target=$(get_vless_reality_field dest)
    old_sni=$(get_vless_server_name)
    old_private=$(get_vless_reality_field privateKey)
    old_short_id=$(get_vless_short_id)
    old_address=$(get_node_field vless address)
    case "$old_address" in
        YOUR_SERVER_IP_OR_DOMAIN) old_address= ;;
    esac
    detected_address=$(detect_server_address)
    echo
    echo '=== 配置/修改 VLESS Reality ==='
    SERVER_ADDRESS=$(prompt_input '服务器域名或 IP（仅用于生成客户端参数，默认读取本机网卡）' "${old_address:-${detected_address:-YOUR_SERVER_IP_OR_DOMAIN}}")
    VLESS_PORT=$(prompt_input 'VLESS 端口' "${old_port:-443}")
    REALITY_TARGET=$(prompt_input 'Reality 伪装目标域名或 HOST:PORT' "${old_target:-www.apple.com:443}")
    REALITY_TARGET=$(normalize_target "$REALITY_TARGET")
    SERVER_NAME=$(prompt_input 'Reality SNI' "${old_sni:-$(derive_server_name "$REALITY_TARGET")}")
    if [ -n "$old_private" ] && yes_no '保留现有 UUID 和 Reality 密钥' yes; then
        VLESS_UUID=${old_uuid:-$(generate_uuid)}
        REALITY_PRIVATE_KEY=$old_private
        derive_reality_public_key
        SHORT_ID=${old_short_id:-$(openssl rand -hex 8 | tr -d '\n')}
    else
        VLESS_UUID=$(generate_uuid)
        SHORT_ID=$(openssl rand -hex 8 | tr -d '\n')
        generate_reality_keys
    fi
    FLOW=${old_flow:-xtls-rprx-vision}

    is_port "$VLESS_PORT" || die "VLESS 端口无效。"
    validate_server_address "$SERVER_ADDRESS" || die "服务器地址格式无效：请填写域名、有效 IPv4 或 IPv6 地址；IPv4 每段必须为 0-255。"
    is_safe_value "$REALITY_TARGET" || die "Reality 目标包含不安全字符。"
    is_safe_value "$SERVER_NAME" || die "Reality SNI 包含不安全字符。"

    inbound_json=$(jq -n \
        --arg listen "::" \
        --arg port "$VLESS_PORT" \
        --arg uuid "$VLESS_UUID" \
        --arg flow "$FLOW" \
        --arg target "$REALITY_TARGET" \
        --arg sni "$SERVER_NAME" \
        --arg private_key "$REALITY_PRIVATE_KEY" \
        --arg short_id "$SHORT_ID" \
        '{tag:"vless-reality-in", listen:$listen, port:($port|tonumber), protocol:"vless", settings:{clients:[{id:$uuid,flow:$flow,email:"vless-reality"}],decryption:"none"}, streamSettings:{network:"raw",security:"reality",realitySettings:{show:false,target:$target,xver:0,serverNames:[$sni],privateKey:$private_key,shortIds:[$short_id]}}, sniffing:{enabled:true,destOverride:["http","tls","quic"]}}')
    write_config "$inbound_json" vless-reality-in vless-in

    client_host=$(format_url_host "$SERVER_ADDRESS")
    vless_url="vless://$VLESS_UUID@$client_host:$VLESS_PORT?encryption=none&security=reality&sni=$SERVER_NAME&fp=chrome&pbk=$REALITY_PUBLIC_KEY&sid=$SHORT_ID&type=tcp&flow=$FLOW#vless-reality"
    show_terminal_qr vless-reality "$vless_url"
    node_json=$(jq -n \
        --arg address "$SERVER_ADDRESS" --arg port "$VLESS_PORT" \
        --arg uuid "$VLESS_UUID" --arg flow "$FLOW" --arg sni "$SERVER_NAME" \
        --arg target "$REALITY_TARGET" --arg public_key "$REALITY_PUBLIC_KEY" \
        --arg private_key "$REALITY_PRIVATE_KEY" --arg short_id "$SHORT_ID" --arg url "$vless_url" \
        '{address:$address,port:($port|tonumber),uuid:$uuid,flow:$flow,sni:$sni,target:$target,publicKey:$public_key,privateKey:$private_key,shortId:$short_id,url:$url}')
    save_node vless "$node_json"
    echo
    echo 'VLESS 节点参数已保存:'
    echo "$vless_url"
    if yes_no '现在重启 Xray 使配置生效' yes; then
        restart_xray
    fi
}

configure_ss() {
    old_port=$(get_ss_field port)
    old_method=$(get_ss_field method)
    old_password=$(get_ss_field password)
    old_address=$(get_node_field ss2022 address)
    case "$old_address" in
        YOUR_SERVER_IP_OR_DOMAIN) old_address= ;;
    esac
    detected_address=$(detect_server_address)
    echo
    echo '=== 配置/修改 Shadowsocks 2022 ==='
    SERVER_ADDRESS=$(prompt_input '服务器域名或 IP（仅用于节点参数，默认读取本机网卡）' "${old_address:-${detected_address:-YOUR_SERVER_IP_OR_DOMAIN}}")
    SS_PORT=$(prompt_input 'SS2022 端口' "${old_port:-8388}")
    choose_ss_method "${old_method:-2022-blake3-aes-256-gcm}"
    is_port "$SS_PORT" || die "SS2022 端口无效。"
    validate_server_address "$SERVER_ADDRESS" || die "服务器地址格式无效：请填写域名、有效 IPv4 或 IPv6 地址；IPv4 每段必须为 0-255。"

    old_key_bytes=$(ss_method_key_bytes "${old_method:-}")
    new_key_bytes=$(ss_method_key_bytes "$SS_METHOD")
    if [ -n "$old_password" ] && [ -n "$old_method" ] && [ "$old_key_bytes" = "$new_key_bytes" ] && yes_no '保留现有 SS2022 密码' yes; then
        SS_PASSWORD=$old_password
    else
        if [ -n "$old_password" ] && [ -n "$old_method" ] && [ "$old_key_bytes" != "$new_key_bytes" ]; then
            info "加密方式密钥长度从 ${old_key_bytes}B 变为 ${new_key_bytes}B，已自动重新生成 SS2022 密码"
        fi
        SS_PASSWORD=$(openssl rand -base64 "$new_key_bytes" | tr -d '\n')
    fi

    inbound_json=$(jq -n \
        --arg listen "::" --arg port "$SS_PORT" --arg method "$SS_METHOD" --arg password "$SS_PASSWORD" \
        '{tag:"ss2022-in",listen:$listen,port:($port|tonumber),protocol:"shadowsocks",settings:{method:$method,password:$password,network:"tcp,udp"}}')
    write_config "$inbound_json" ss2022-in ''
    make_ss_url "$SERVER_ADDRESS" "$SS_PORT" "$SS_METHOD" "$SS_PASSWORD"
    show_terminal_qr ss2022 "$SS_URL"
    node_json=$(jq -n \
        --arg address "$SERVER_ADDRESS" --arg port "$SS_PORT" \
        --arg method "$SS_METHOD" --arg password "$SS_PASSWORD" --arg url "$SS_URL" \
        '{address:$address,port:($port|tonumber),method:$method,password:$password,url:$url}')
    save_node ss2022 "$node_json"
    echo
    echo 'SS2022 节点参数已保存:'
    echo "地址: $SERVER_ADDRESS"
    echo "端口: $SS_PORT"
    echo "加密: $SS_METHOD"
    echo "密码: $SS_PASSWORD"
    echo "$SS_URL"
    if yes_no '现在重启 Xray 使配置生效' yes; then
        restart_xray
    fi
}

configure_hy2() {
    old_port=$(get_hy2_field port)
    old_address=$(get_node_field hy2 address)
    case "$old_address" in
        YOUR_SERVER_IP_OR_DOMAIN) old_address= ;;
    esac
    detected_address=$(detect_server_address)
    old_sni=$(get_hy2_tls_field serverName)
    old_cert=$(get_hy2_certificate_field certificateFile)
    old_key=$(get_hy2_certificate_field keyFile)
    old_password=$(get_hy2_password)
    old_mport=$(get_node_field hy2 mport)
    echo
    echo '=== 配置/修改 Hysteria2 ==='
    SERVER_ADDRESS=$(prompt_input '服务器域名或 IP（仅用于节点参数，默认读取本机网卡）' "${old_address:-${detected_address:-YOUR_SERVER_IP_OR_DOMAIN}}")
    HY2_PORT=$(prompt_input 'Hysteria2 UDP 端口' "${old_port:-443}")
    HY2_SNI=$(prompt_input 'TLS SNI/证书域名' "${old_sni:-$SERVER_ADDRESS}")
    HY2_CERT_FILE=$(prompt_input 'TLS 证书文件完整路径' "$old_cert")
    HY2_KEY_FILE=$(prompt_input 'TLS 私钥文件完整路径' "$old_key")
    HY2_PASSWORD=$(prompt_input 'Hysteria2 密码' "${old_password:-$(openssl rand -hex 16)}")
    HY2_MPORT=$(prompt_input '端口跳跃范围（可选，如 20000-50000，留空不启用，输入 none 清除）' "$old_mport")
    case "$HY2_MPORT" in
        none|NONE|-) HY2_MPORT= ;;
        *) HY2_MPORT=$(printf '%s' "$HY2_MPORT" | tr -d '[:space:]') ;;
    esac

    is_port "$HY2_PORT" || die "Hysteria2 端口无效。"
    validate_server_address "$SERVER_ADDRESS" || die "服务器地址格式无效：请填写域名、有效 IPv4 或 IPv6 地址；IPv4 每段必须为 0-255。"
    is_safe_value "$HY2_SNI" || die "TLS SNI 包含不支持的字符。"
    [ -n "$HY2_PASSWORD" ] || die "Hysteria2 密码不能为空。"
    [ -z "$HY2_MPORT" ] || is_valid_mport "$HY2_MPORT" || die "端口跳跃范围格式无效，请填写如 20000-50000 或 20000-30000,40000-50000。"
    [ -r "$HY2_CERT_FILE" ] || die "证书文件不可读: $HY2_CERT_FILE"
    [ -r "$HY2_KEY_FILE" ] || die "私钥文件不可读: $HY2_KEY_FILE"
    warn_cert_permissions "$HY2_CERT_FILE"
    warn_cert_permissions "$HY2_KEY_FILE"

    inbound_json=$(jq -n \
        --arg listen "::" --arg port "$HY2_PORT" --arg password "$HY2_PASSWORD" \
        --arg sni "$HY2_SNI" --arg cert "$HY2_CERT_FILE" --arg key "$HY2_KEY_FILE" \
        '{tag:"hysteria2-in",listen:$listen,port:($port|tonumber),protocol:"hysteria",settings:{version:2},streamSettings:{network:"hysteria",security:"tls",tlsSettings:{serverName:$sni,alpn:["h3"],certificates:[{usage:"encipherment",certificateFile:$cert,keyFile:$key}]},hysteriaSettings:{version:2,auth:$password}}}')
    write_config "$inbound_json" hysteria2-in hy2-in
    make_hy2_url "$SERVER_ADDRESS" "$HY2_PORT" "$HY2_PASSWORD" "$HY2_SNI" "$HY2_MPORT"
    show_terminal_qr hysteria2 "$HY2_URL"
    node_json=$(jq -n \
        --arg address "$SERVER_ADDRESS" --arg port "$HY2_PORT" \
        --arg password "$HY2_PASSWORD" --arg sni "$HY2_SNI" \
        --arg cert "$HY2_CERT_FILE" --arg key "$HY2_KEY_FILE" \
        --arg mport "$HY2_MPORT" --arg url "$HY2_URL" \
        '{address:$address,port:($port|tonumber),password:$password,sni:$sni,certificateFile:$cert,keyFile:$key,mport:$mport,url:$url}')
    save_node hy2 "$node_json"
    echo
    echo 'Hysteria2 节点参数已保存:'
    echo "地址: $SERVER_ADDRESS"
    echo "端口: $HY2_PORT/UDP"
    echo "SNI: $HY2_SNI"
    echo "证书: $HY2_CERT_FILE"
    echo "私钥: $HY2_KEY_FILE"
    echo "密码: $HY2_PASSWORD"
    [ -z "$HY2_MPORT" ] || echo "端口跳跃: $HY2_MPORT"
    echo "$HY2_URL"
    [ -z "$HY2_MPORT" ] || print_hy2_hopping_commands "$HY2_PORT" "$HY2_MPORT"
    if yes_no '现在重启 Xray 使配置生效' yes; then
        restart_xray
    fi
}

configure_xhttp() {
    old_port=$(get_xhttp_field port)
    old_listen=$(get_xhttp_field listen)
    old_uuid=$(get_xhttp_uuid)
    old_path=$(get_xhttp_setting path)
    old_host=$(get_xhttp_setting host)
    old_mode=$(get_xhttp_setting mode)
    old_security=$(get_xhttp_security)
    old_target=$(get_xhttp_reality_field target)
    [ -n "$old_target" ] || old_target=$(get_xhttp_reality_field dest)
    old_reality_sni=$(get_xhttp_reality_sni)
    old_private=$(get_xhttp_reality_field privateKey)
    old_short_id=$(get_xhttp_reality_short_id)
    old_tls_sni=$(get_xhttp_tls_field serverName)
    old_cert=$(get_xhttp_certificate_field certificateFile)
    old_key=$(get_xhttp_certificate_field keyFile)
    old_extra=$(get_xhttp_extra)
    old_xff=$(get_xhttp_trusted_xff)
    old_address=$(get_node_field xhttp address)
    case "$old_address" in
        YOUR_SERVER_IP_OR_DOMAIN) old_address= ;;
    esac
    detected_address=$(detect_server_address)
    default_path=${old_path:-"/$(openssl rand -hex 6)"}

    echo
    echo '=== 配置/修改 VLESS XHTTP ==='
    SERVER_ADDRESS=$(prompt_input '服务器域名或 IP（仅用于生成客户端参数，默认读取本机网卡）' "${old_address:-${detected_address:-YOUR_SERVER_IP_OR_DOMAIN}}")
    XHTTP_PORT=$(prompt_input 'VLESS XHTTP 端口' "${old_port:-443}")
    XHTTP_PATH=$(prompt_input 'XHTTP 路径（如 /xhttp）' "$default_path")
    XHTTP_PATH=$(normalize_xhttp_path "$XHTTP_PATH")
    XHTTP_HOST=$(prompt_input 'XHTTP Host（可选，直接回车留空）' "$old_host")
    choose_xhttp_mode "${old_mode:-auto}"
    choose_xhttp_security "${old_security:-reality}"

    is_port "$XHTTP_PORT" || die "VLESS XHTTP 端口无效。"
    validate_server_address "$SERVER_ADDRESS" || die "服务器地址格式无效：请填写域名、有效 IPv4 或 IPv6 地址；IPv4 每段必须为 0-255。"
    is_safe_xhttp_path "$XHTTP_PATH" || die "XHTTP 路径包含不支持的字符（仅支持字母、数字及 / . _ ~ -）。"
    if [ -n "$XHTTP_HOST" ]; then
        is_safe_value "$XHTTP_HOST" || die "XHTTP Host 包含不支持的字符。"
    fi

    XHTTP_LISTEN='::'
    XHTTP_SNI=
    XHTTP_TARGET=
    XHTTP_CERT_FILE=
    XHTTP_KEY_FILE=
    XHTTP_XFF=
    REALITY_PRIVATE_KEY=
    REALITY_PUBLIC_KEY=
    SHORT_ID=

    case "$XHTTP_SECURITY" in
        reality)
            XHTTP_TARGET=$(prompt_input 'Reality 伪装目标域名或 HOST:PORT' "${old_target:-www.apple.com:443}")
            XHTTP_TARGET=$(normalize_target "$XHTTP_TARGET")
            XHTTP_SNI=$(prompt_input 'Reality SNI' "${old_reality_sni:-$(derive_server_name "$XHTTP_TARGET")}")
            is_safe_value "$XHTTP_TARGET" || die "Reality 目标包含不安全字符。"
            is_safe_value "$XHTTP_SNI" || die "Reality SNI 包含不安全字符。"
            if [ -n "$old_private" ] && yes_no '保留现有 UUID 和 Reality 密钥' yes; then
                XHTTP_UUID=${old_uuid:-$(generate_uuid)}
                REALITY_PRIVATE_KEY=$old_private
                derive_reality_public_key
                SHORT_ID=${old_short_id:-$(openssl rand -hex 8 | tr -d '\n')}
            else
                XHTTP_UUID=$(generate_uuid)
                SHORT_ID=$(openssl rand -hex 8 | tr -d '\n')
                generate_reality_keys
            fi
            inbound_json=$(jq -n \
                --arg listen "$XHTTP_LISTEN" \
                --arg port "$XHTTP_PORT" \
                --arg uuid "$XHTTP_UUID" \
                --arg path "$XHTTP_PATH" \
                --arg host "$XHTTP_HOST" \
                --arg mode "$XHTTP_MODE" \
                --arg extra "$old_extra" \
                --arg target "$XHTTP_TARGET" \
                --arg sni "$XHTTP_SNI" \
                --arg private_key "$REALITY_PRIVATE_KEY" \
                --arg short_id "$SHORT_ID" \
                '{tag:"vless-xhttp-in", listen:$listen, port:($port|tonumber), protocol:"vless", settings:{clients:[{id:$uuid,email:"vless-xhttp"}],decryption:"none"}, streamSettings:{network:"xhttp",security:"reality",xhttpSettings:({path:$path,mode:$mode} + (if $host != "" then {host:$host} else {} end) + (if $extra != "" then {extra:($extra|fromjson)} else {} end)),realitySettings:{show:false,target:$target,xver:0,serverNames:[$sni],privateKey:$private_key,shortIds:[$short_id]}}, sniffing:{enabled:true,destOverride:["http","tls","quic"]}}')
            ;;
        tls)
            XHTTP_SNI=$(prompt_input 'TLS SNI/证书域名' "${old_tls_sni:-$SERVER_ADDRESS}")
            XHTTP_CERT_FILE=$(prompt_input 'TLS 证书文件完整路径' "$old_cert")
            XHTTP_KEY_FILE=$(prompt_input 'TLS 私钥文件完整路径' "$old_key")
            choose_xhttp_xff "$old_xff"
            is_safe_value "$XHTTP_SNI" || die "TLS SNI 包含不支持的字符。"
            [ -r "$XHTTP_CERT_FILE" ] || die "证书文件不可读: $XHTTP_CERT_FILE"
            [ -r "$XHTTP_KEY_FILE" ] || die "私钥文件不可读: $XHTTP_KEY_FILE"
            warn_cert_permissions "$XHTTP_CERT_FILE"
            warn_cert_permissions "$XHTTP_KEY_FILE"
            if [ -n "$old_uuid" ] && yes_no '保留现有 UUID' yes; then
                XHTTP_UUID=$old_uuid
            else
                XHTTP_UUID=$(generate_uuid)
            fi
            inbound_json=$(jq -n \
                --arg listen "$XHTTP_LISTEN" \
                --arg port "$XHTTP_PORT" \
                --arg uuid "$XHTTP_UUID" \
                --arg path "$XHTTP_PATH" \
                --arg host "$XHTTP_HOST" \
                --arg mode "$XHTTP_MODE" \
                --arg extra "$old_extra" \
                --arg xff "$XHTTP_XFF" \
                --arg sni "$XHTTP_SNI" \
                --arg cert "$XHTTP_CERT_FILE" \
                --arg key "$XHTTP_KEY_FILE" \
                '{tag:"vless-xhttp-in", listen:$listen, port:($port|tonumber), protocol:"vless", settings:{clients:[{id:$uuid,email:"vless-xhttp"}],decryption:"none"}, streamSettings:({network:"xhttp",security:"tls",xhttpSettings:({path:$path,mode:$mode} + (if $host != "" then {host:$host} else {} end) + (if $extra != "" then {extra:($extra|fromjson)} else {} end)),tlsSettings:{serverName:$sni,alpn:["h2","http/1.1"],certificates:[{usage:"encipherment",certificateFile:$cert,keyFile:$key}]}} + (if $xff != "" then {sockopt:{trustedXForwardedFor:($xff|split(",")|map(select(length>0)))}} else {} end)), sniffing:{enabled:true,destOverride:["http","tls","quic"]}}')
            ;;
        none)
            XHTTP_LISTEN=$(prompt_input '监听地址（本机反代推荐 127.0.0.1）' "${old_listen:-127.0.0.1}")
            is_safe_value "$XHTTP_LISTEN" || die "监听地址包含不支持的字符。"
            choose_xhttp_xff "$old_xff"
            if [ -n "$old_uuid" ] && yes_no '保留现有 UUID' yes; then
                XHTTP_UUID=$old_uuid
            else
                XHTTP_UUID=$(generate_uuid)
            fi
            inbound_json=$(jq -n \
                --arg listen "$XHTTP_LISTEN" \
                --arg port "$XHTTP_PORT" \
                --arg uuid "$XHTTP_UUID" \
                --arg path "$XHTTP_PATH" \
                --arg host "$XHTTP_HOST" \
                --arg mode "$XHTTP_MODE" \
                --arg extra "$old_extra" \
                --arg xff "$XHTTP_XFF" \
                '{tag:"vless-xhttp-in", listen:$listen, port:($port|tonumber), protocol:"vless", settings:{clients:[{id:$uuid,email:"vless-xhttp"}],decryption:"none"}, streamSettings:({network:"xhttp",security:"none",xhttpSettings:({path:$path,mode:$mode} + (if $host != "" then {host:$host} else {} end) + (if $extra != "" then {extra:($extra|fromjson)} else {} end))} + (if $xff != "" then {sockopt:{trustedXForwardedFor:($xff|split(",")|map(select(length>0)))}} else {} end)), sniffing:{enabled:true,destOverride:["http","tls","quic"]}}')
            ;;
    esac

    write_config "$inbound_json" vless-xhttp-in xhttp-in
    make_xhttp_url "$SERVER_ADDRESS" "$XHTTP_PORT" "$XHTTP_UUID" "$XHTTP_PATH" "$XHTTP_MODE" "$XHTTP_SECURITY" "$XHTTP_SNI" "$REALITY_PUBLIC_KEY" "$SHORT_ID" "$XHTTP_HOST" "$old_extra"
    show_terminal_qr vless-xhttp "$XHTTP_URL"
    node_json=$(jq -n \
        --arg address "$SERVER_ADDRESS" --arg port "$XHTTP_PORT" \
        --arg listen "$XHTTP_LISTEN" --arg uuid "$XHTTP_UUID" \
        --arg path "$XHTTP_PATH" --arg host "$XHTTP_HOST" \
        --arg mode "$XHTTP_MODE" --arg security "$XHTTP_SECURITY" \
        --arg xff "$XHTTP_XFF" \
        --arg sni "$XHTTP_SNI" --arg target "$XHTTP_TARGET" \
        --arg public_key "$REALITY_PUBLIC_KEY" --arg private_key "$REALITY_PRIVATE_KEY" \
        --arg short_id "$SHORT_ID" --arg cert "$XHTTP_CERT_FILE" \
        --arg key "$XHTTP_KEY_FILE" --arg url "$XHTTP_URL" \
        '{address:$address,port:($port|tonumber),listen:$listen,uuid:$uuid,path:$path,host:$host,mode:$mode,security:$security,trustedXForwardedFor:$xff,sni:$sni,target:$target,publicKey:$public_key,privateKey:$private_key,shortId:$short_id,certificateFile:$cert,keyFile:$key,url:$url}')
    save_node xhttp "$node_json"
    echo
    echo 'VLESS XHTTP 节点参数已保存:'
    echo "地址: $SERVER_ADDRESS"
    echo "端口: $XHTTP_PORT"
    echo "路径: $XHTTP_PATH"
    echo "模式: $XHTTP_MODE"
    echo "传输安全: $XHTTP_SECURITY"
    [ -z "$XHTTP_HOST" ] || echo "Host: $XHTTP_HOST"
    [ -z "$XHTTP_XFF" ] || echo "信任 XFF 头部: $XHTTP_XFF"
    [ -z "$old_extra" ] || echo "Extra: $old_extra"
    echo "$XHTTP_URL"
    if yes_no '现在重启 Xray 使配置生效' yes; then
        restart_xray
    fi
}

configure_socks_outbound() {
    old_addr=$(get_warp_field address)
    old_port=$(get_warp_field port)
    old_user=$(get_warp_user)
    old_pass=$(get_warp_pass)
    old_domains=$(get_warp_route_domains)

    echo
    echo '=== 配置 SOCKS5 / WARP 出口路由 ==='
    echo "当前状态: $(get_warp_route_summary)"
    echo '提示: 如需在本机部署 WARP SOCKS5 代理（默认监听 127.0.0.1:40000），可先运行:'
    echo '  wget -N https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh && bash menu.sh'
    echo
    printf '%s\n' \
        '请选择出口路由模式:' \
        '  1) 全局走 SOCKS5 / WARP 出口' \
        '  2) 按域名分流走 SOCKS5 / WARP（其余走直连）' \
        '  3) 仅添加 warp 出站，不修改路由规则' \
        '  4) 移除 warp 出站和对应路由规则（恢复直连）' \
        '  0) 取消' > /dev/tty
    route_choice=$(prompt_input '请选择' '1')

    tmp_config="$CONFIG_FILE.warp.$$.json"
    case "$route_choice" in
        0|q|Q)
            echo '已取消。'
            return 0
            ;;
        4)
            jq '.outbounds = ((.outbounds // []) | map(select((.tag // "") != "warp")))
                | if .routing.rules then .routing.rules = (.routing.rules | map(select((.outboundTag // "") != "warp"))) else . end' \
                "$CONFIG_FILE" > "$tmp_config" || {
                rm -f "$tmp_config"
                die '生成移除 warp 后的配置失败。'
            }
            info "检查 Xray 配置"
            if ! "$XRAY_BIN" run -test -format json -config "$tmp_config"; then
                rm -f "$tmp_config"
                die '配置检查失败，未修改配置。'
            fi
            mv "$tmp_config" "$CONFIG_FILE"
            chmod 644 "$CONFIG_FILE"
            echo '已移除 warp SOCKS5 出站和对应路由规则。'
            if yes_no '现在重启 Xray 使配置生效' yes; then
                restart_xray
            fi
            return 0
            ;;
        1|2|3) : ;;
        *) die '选择无效，请输入 0-4。' ;;
    esac

    SOCKS_ADDR=$(prompt_input 'SOCKS5 代理地址' "${old_addr:-127.0.0.1}")
    SOCKS_PORT=$(prompt_input 'SOCKS5 代理端口' "${old_port:-40000}")
    SOCKS_USER=$(prompt_input 'SOCKS5 用户名（可选，无认证直接回车）' "$old_user")
    SOCKS_PASS=
    if [ -n "$SOCKS_USER" ]; then
        SOCKS_PASS=$(prompt_input 'SOCKS5 密码' "$old_pass")
    fi

    validate_server_address "$SOCKS_ADDR" || die "SOCKS5 地址格式无效。"
    is_port "$SOCKS_PORT" || die "SOCKS5 端口无效。"

    WARP_DOMAINS=
    if [ "$route_choice" = 2 ]; then
        WARP_DOMAINS=$(prompt_input '分流域名/geosite（逗号分隔，如 geosite:openai,geosite:netflix,geosite:google）' "${old_domains:-geosite:openai,geosite:netflix}")
        WARP_DOMAINS=$(printf '%s' "$WARP_DOMAINS" | tr -d '[:space:]')
        [ -n "$WARP_DOMAINS" ] || die '分流域名不能为空。'
    fi

    warp_outbound=$(jq -n \
        --arg addr "$SOCKS_ADDR" \
        --arg port "$SOCKS_PORT" \
        --arg user "$SOCKS_USER" \
        --arg pass "$SOCKS_PASS" \
        '{protocol:"socks", settings:{servers:[({address:$addr, port:($port|tonumber)} + (if $user != "" then {users:[{user:$user, pass:$pass}]} else {} end))]}, tag:"warp"}')

    case "$route_choice" in
        1)
            jq --argjson warp "$warp_outbound" \
                '.outbounds = (((.outbounds // []) | map(select((.tag // "") != "warp"))) + [$warp])
                 | .routing = ((.routing // {}) + {
                     domainStrategy: (.routing.domainStrategy // "AsIs"),
                     rules: (((.routing.rules // []) | map(select((.outboundTag // "") != "warp"))) + [{type:"field", network:"tcp,udp", outboundTag:"warp"}])
                   })' "$CONFIG_FILE" > "$tmp_config"
            ;;
        2)
            jq --argjson warp "$warp_outbound" --arg domains "$WARP_DOMAINS" \
                '.outbounds = (((.outbounds // []) | map(select((.tag // "") != "warp"))) + [$warp])
                 | .routing = ((.routing // {}) + {
                     domainStrategy: (.routing.domainStrategy // "AsIs"),
                     rules: ([{type:"field", domain:($domains | split(",") | map(select(length > 0))), outboundTag:"warp"}] + ((.routing.rules // []) | map(select((.outboundTag // "") != "warp"))))
                   })' "$CONFIG_FILE" > "$tmp_config"
            ;;
        3)
            jq --argjson warp "$warp_outbound" \
                '.outbounds = (((.outbounds // []) | map(select((.tag // "") != "warp"))) + [$warp])' \
                "$CONFIG_FILE" > "$tmp_config"
            ;;
    esac || {
        rm -f "$tmp_config"
        die '生成 SOCKS5 / WARP 出口配置失败。'
    }

    info "检查 Xray 配置"
    if ! "$XRAY_BIN" run -test -format json -config "$tmp_config"; then
        rm -f "$tmp_config"
        die '配置检查失败，SOCKS5 / WARP 出口未修改。'
    fi
    mv "$tmp_config" "$CONFIG_FILE"
    chmod 644 "$CONFIG_FILE"
    echo "SOCKS5 / WARP 出口配置已保存: $(get_warp_route_summary)"
    if yes_no '现在重启 Xray 使配置生效' yes; then
        restart_xray
    fi
}

menu() {
    [ -r /dev/tty ] && [ -w /dev/tty ] || die "交互菜单需要可用的终端。"
    while :; do
        printf '%s\n' '' '========= Xray 管理菜单 =========' \
            '1) 配置/修改 VLESS Reality' \
            '2) 配置/修改 Shadowsocks 2022' \
            '3) 配置/修改 Hysteria2' \
            '4) 配置/修改 VLESS XHTTP' \
            '5) 重启 Xray' \
            '6) 查看状态' \
            '7) 查看节点和配置摘要' \
            '8) 卸载 Xray（可选择保留备份或清空）' \
            '9) 编辑 Xray 配置文件' \
            '10) 删除 VLESS Reality、Shadowsocks 2022、Hysteria2 或 VLESS XHTTP' \
            '11) 设置所有 Freedom 直连出站的 IP 模式' \
            '12) 配置 SOCKS5 / WARP 出口路由' \
            '0) 退出' \
            '=================================' > /dev/tty
        choice=$(prompt_input '请选择' '')
        case "$choice" in
            1) configure_vless ;;
            2) configure_ss ;;
            3) configure_hy2 ;;
            4) configure_xhttp ;;
            5) restart_xray ;;
            6) show_status ;;
            7) show_summary ;;
            8) uninstall_xray ;;
            9) edit_config ;;
            10) remove_protocol ;;
            11) configure_outbound_mode ;;
            12) configure_socks_outbound ;;
            0|q|Q) exit 0 ;;
            *) echo '选择无效，请输入 0-12。' ;;
        esac
    done
}

main() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h|--help) usage; exit 0 ;;
            --vless) ACTION=vless ;;
            --ss|--ss2022) ACTION=ss ;;
            --hy2|--hysteria2) ACTION=hy2 ;;
            --xhttp) ACTION=xhttp ;;
            --warp|--socks-outbound) ACTION=warp ;;
            --edit) ACTION=edit ;;
            --remove) ACTION=remove ;;
            --remove-vless) ACTION=remove; REMOVE_PROTO=vless ;;
            --remove-ss|--remove-ss2022) ACTION=remove; REMOVE_PROTO=ss2022 ;;
            --remove-hy2|--remove-hysteria2) ACTION=remove; REMOVE_PROTO=hy2 ;;
            --remove-xhttp) ACTION=remove; REMOVE_PROTO=xhttp ;;
            --restart) ACTION=restart ;;
            --status) ACTION=status ;;
            --uninstall) ACTION=uninstall ;;
            --purge) PURGE_DATA=1 ;;
            --yes|-y) ASSUME_YES=1 ;;
            *) die "未知参数: $1（使用 --help 查看帮助）" ;;
        esac
        shift
    done

    require_root
    detect_os

    if [ "$ACTION" = uninstall ]; then
        uninstall_xray
        exit 0
    fi

    install_dependencies
    install_xray
    ensure_base_files

    case "$ACTION" in
        vless) configure_vless ;;
        ss) configure_ss ;;
        hy2) configure_hy2 ;;
        xhttp) configure_xhttp ;;
        warp) configure_socks_outbound ;;
        edit) edit_config ;;
        remove) remove_protocol ;;
        restart) restart_xray ;;
        status) show_status ;;
        '') menu ;;
    esac
}

main "$@"
