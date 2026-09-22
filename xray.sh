#!/bin/sh
# Interactive Xray manager for VLESS REALITY and Shadowsocks 2022.
# Supports Debian/Ubuntu (systemd) and Alpine (OpenRC).

set -eu

XRAY_BIN=${XRAY_BIN:-/usr/local/bin/xray}
XRAY_DIR=${XRAY_DIR:-/usr/local/etc/xray}
CONFIG_FILE=${CONFIG_FILE:-$XRAY_DIR/config.json}
NODES_FILE=${NODES_FILE:-/root/xray-nodes.json}
ACTION=
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
    info "检查并安装系统依赖，请稍候..."
    if [ "$OS" = alpine ]; then
        info "使用 apk 安装 curl、tar、openssl、ca-certificates 和 jq"
        apk add --no-cache curl tar openssl ca-certificates jq >/dev/null
        # qrencode is optional; some Alpine releases provide it as a community subpackage.
        info "尝试安装终端二维码工具 qrencode（可选）"
        apk add --no-cache libqrencode-tools >/dev/null 2>&1 || true
    else
        export DEBIAN_FRONTEND=noninteractive
        info "使用 apt 更新软件包索引"
        apt-get update -qq
        info "使用 apt 安装 curl、tar、openssl、ca-certificates、jq 和 qrencode"
        apt-get install -y -qq curl tar openssl ca-certificates jq qrencode >/dev/null
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
    jq -r 'first(.outbounds[]? | select(.protocol == "freedom") | .settings.domainStrategy) // "UseIPv6v4"' "$CONFIG_FILE"
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

make_ss_url() {
    server_address=$1
    ss_port_value=$2
    ss_method_value=$3
    ss_password_value=$4
    ss_host=$server_address
    case "$ss_host" in
        *:*) ss_host="[$ss_host]" ;;
    esac
    ss_userinfo=$(printf '%s' "$ss_method_value:$ss_password_value" | openssl base64 -A | tr '+/' '-_' | tr -d '=')
    SS_URL="ss://$ss_userinfo@$ss_host:$ss_port_value#ss2022"
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

get_vless_short_id() {
    jq -r 'first(.inbounds[]? | select(.tag == "vless-reality-in" or .tag == "vless-in") | .streamSettings.realitySettings.shortIds[0]) // empty' "$CONFIG_FILE"
}

is_port() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ "$1" -ge 1 ] 2>/dev/null && [ "$1" -le 65535 ] 2>/dev/null
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
    if IFS= read -r answer < /dev/tty; then
        :
    else
        answer=
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

choose_ip_mode() {
    default_mode=$1
    printf '%s\n' \
        'IP 模式:' \
        '  1) dual  双栈，IPv6 优先，失败回落 IPv4' \
        '  2) ipv4  仅 IPv4' \
        '  3) ipv6  仅 IPv6' > /dev/tty
    choice=$(prompt_input '请选择' "$default_mode")
    case "$choice" in
        1|dual) IP_MODE=dual; LISTEN_ADDR=::; DOMAIN_STRATEGY=UseIPv6v4 ;;
        2|ipv4) IP_MODE=ipv4; LISTEN_ADDR=0.0.0.0; DOMAIN_STRATEGY=UseIPv4 ;;
        3|ipv6) IP_MODE=ipv6; LISTEN_ADDR=::; DOMAIN_STRATEGY=UseIPv6 ;;
        *) die "IP 模式只能选择 1、2、3、dual 或 ipv4/ipv6。" ;;
    esac
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
    REALITY_PUBLIC_KEY=$(printf '%s\n' "$key_output" | awk -F': *' 'tolower($1) ~ /password/ {print $2; exit}')
    [ -n "$REALITY_PRIVATE_KEY" ] || die "无法解析 Reality private key。"
    [ -n "$REALITY_PUBLIC_KEY" ] || die "无法解析 Reality public key。"
}

derive_reality_public_key() {
    key_output=$($XRAY_BIN x25519 -i "$REALITY_PRIVATE_KEY" 2>/dev/null) || die "无法从现有 private key 生成 public key。"
    REALITY_PUBLIC_KEY=$(printf '%s\n' "$key_output" | awk -F': *' 'tolower($1) ~ /password/ {print $2; exit}')
    [ -n "$REALITY_PUBLIC_KEY" ] || die "无法解析 Reality public key。"
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
       --arg strategy "$DOMAIN_STRATEGY" \
       --arg remove_one "$remove_tag_one" \
       --arg remove_two "$remove_tag_two" \
       '.log = ((.log // {}) + {
          loglevel: (.log.loglevel // "warning"),
          access: (.log.access // "/var/log/xray/access.log"),
          error: (.log.error // "/var/log/xray/error.log")
        })
        | .inbounds = ((.inbounds // []) | map(select((.tag // "") != $remove_one and (.tag // "") != $remove_two)) + [$inbound])
        | .outbounds = (if any(.outbounds[]?; .protocol == "freedom") then
            (.outbounds | map(if .protocol == "freedom" then .settings = ((.settings // {}) + {domainStrategy: $strategy}) else . end))
          else
            ((.outbounds // []) + [{tag: "direct", protocol: "freedom", settings: {domainStrategy: $strategy}}])
          end)' "$CONFIG_FILE" > "$tmp_config"

    info "检查 Xray 配置"
    "$XRAY_BIN" run -test -format json -config "$tmp_config"
    backup="$CONFIG_FILE.bak.$(date +%Y%m%d%H%M%S)"
    cp -p "$CONFIG_FILE" "$backup"
    mv "$tmp_config" "$CONFIG_FILE"
    chmod 644 "$CONFIG_FILE"
    echo "配置已保存，旧配置备份: $backup"
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
    echo "配置文件: $CONFIG_FILE"
    echo "节点参数: $NODES_FILE"
    show_vless_node
    show_ss_node
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
    old_mode=$(get_node_field vless ipMode)
    [ -n "$old_mode" ] || old_mode=dual

    echo
    echo '=== 配置/修改 VLESS Reality ==='
    SERVER_ADDRESS=$(prompt_input '服务器域名或 IP（仅用于生成客户端参数）' "${old_address:-YOUR_SERVER_IP_OR_DOMAIN}")
    VLESS_PORT=$(prompt_input 'VLESS 端口' "${old_port:-443}")
    REALITY_TARGET=$(prompt_input 'Reality 伪装目标域名或 HOST:PORT' "${old_target:-www.apple.com:443}")
    REALITY_TARGET=$(normalize_target "$REALITY_TARGET")
    SERVER_NAME=$(prompt_input 'Reality SNI' "${old_sni:-$(derive_server_name "$REALITY_TARGET")}")
    choose_ip_mode "$old_mode"

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
        --arg listen "$LISTEN_ADDR" \
        --arg port "$VLESS_PORT" \
        --arg uuid "$VLESS_UUID" \
        --arg flow "$FLOW" \
        --arg target "$REALITY_TARGET" \
        --arg sni "$SERVER_NAME" \
        --arg private_key "$REALITY_PRIVATE_KEY" \
        --arg short_id "$SHORT_ID" \
        '{tag:"vless-reality-in", listen:$listen, port:($port|tonumber), protocol:"vless", settings:{clients:[{id:$uuid,flow:$flow,email:"vless-reality"}],decryption:"none"}, streamSettings:{network:"raw",security:"reality",realitySettings:{show:false,target:$target,xver:0,serverNames:[$sni],privateKey:$private_key,shortIds:[$short_id]}}, sniffing:{enabled:true,destOverride:["http","tls","quic"]}}')
    write_config "$inbound_json" vless-reality-in vless-in

    client_host=$SERVER_ADDRESS
    case "$client_host" in
        *:*) client_host="[$client_host]" ;;
    esac
    vless_url="vless://$VLESS_UUID@$client_host:$VLESS_PORT?encryption=none&security=reality&sni=$SERVER_NAME&fp=chrome&pbk=$REALITY_PUBLIC_KEY&sid=$SHORT_ID&type=tcp&flow=$FLOW#vless-reality"
    show_terminal_qr vless-reality "$vless_url"
    node_json=$(jq -n \
        --arg address "$SERVER_ADDRESS" --arg port "$VLESS_PORT" --arg mode "$IP_MODE" \
        --arg uuid "$VLESS_UUID" --arg flow "$FLOW" --arg sni "$SERVER_NAME" \
        --arg target "$REALITY_TARGET" --arg public_key "$REALITY_PUBLIC_KEY" \
        --arg private_key "$REALITY_PRIVATE_KEY" --arg short_id "$SHORT_ID" --arg url "$vless_url" \
        '{address:$address,port:($port|tonumber),ipMode:$mode,uuid:$uuid,flow:$flow,sni:$sni,target:$target,publicKey:$public_key,privateKey:$private_key,shortId:$short_id,url:$url}')
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
    old_mode=$(get_node_field ss2022 ipMode)
    [ -n "$old_mode" ] || old_mode=dual

    echo
    echo '=== 配置/修改 Shadowsocks 2022 ==='
    SERVER_ADDRESS=$(prompt_input '服务器域名或 IP（仅用于节点参数）' "${old_address:-YOUR_SERVER_IP_OR_DOMAIN}")
    SS_PORT=$(prompt_input 'SS2022 端口' "${old_port:-8388}")
    choose_ss_method "${old_method:-2022-blake3-aes-256-gcm}"
    choose_ip_mode "$old_mode"
    is_port "$SS_PORT" || die "SS2022 端口无效。"
    validate_server_address "$SERVER_ADDRESS" || die "服务器地址格式无效：请填写域名、有效 IPv4 或 IPv6 地址；IPv4 每段必须为 0-255。"

    if [ -n "$old_password" ] && yes_no '保留现有 SS2022 密码' yes; then
        SS_PASSWORD=$old_password
    else
        case "$SS_METHOD" in
            2022-blake3-aes-128-gcm) SS_PASSWORD=$(openssl rand -base64 16 | tr -d '\n') ;;
            *) SS_PASSWORD=$(openssl rand -base64 32 | tr -d '\n') ;;
        esac
    fi

    inbound_json=$(jq -n \
        --arg listen "$LISTEN_ADDR" --arg port "$SS_PORT" --arg method "$SS_METHOD" --arg password "$SS_PASSWORD" \
        '{tag:"ss2022-in",listen:$listen,port:($port|tonumber),protocol:"shadowsocks",settings:{method:$method,password:$password,network:"tcp,udp"}}')
    write_config "$inbound_json" ss2022-in ''
    make_ss_url "$SERVER_ADDRESS" "$SS_PORT" "$SS_METHOD" "$SS_PASSWORD"
    show_terminal_qr ss2022 "$SS_URL"
    node_json=$(jq -n \
        --arg address "$SERVER_ADDRESS" --arg port "$SS_PORT" --arg mode "$IP_MODE" \
        --arg method "$SS_METHOD" --arg password "$SS_PASSWORD" --arg url "$SS_URL" \
        '{address:$address,port:($port|tonumber),ipMode:$mode,method:$method,password:$password,url:$url}')
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

menu() {
    [ -r /dev/tty ] && [ -w /dev/tty ] || die "交互菜单需要可用的终端。"
    while :; do
        printf '%s\n' '' '========= Xray 管理菜单 =========' \
            '1) 配置/修改 VLESS Reality' \
            '2) 配置/修改 Shadowsocks 2022' \
            '3) 重启 Xray' \
            '4) 查看状态' \
            '5) 查看节点和配置摘要' \
            '6) 卸载 Xray（可选择保留备份或清空）' \
            '0) 退出' \
            '=================================' > /dev/tty
        choice=$(prompt_input '请选择' '')
        case "$choice" in
            1) configure_vless ;;
            2) configure_ss ;;
            3) restart_xray ;;
            4) show_status ;;
            5) show_summary ;;
            6) uninstall_xray ;;
            0|q|Q) exit 0 ;;
            *) echo '选择无效，请输入 0-5。' ;;
        esac
    done
}

main() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h|--help) usage; exit 0 ;;
            --vless) ACTION=vless ;;
            --ss|--ss2022) ACTION=ss ;;
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
        restart) restart_xray ;;
        status) show_status ;;
        '') menu ;;
    esac
}

main "$@"
