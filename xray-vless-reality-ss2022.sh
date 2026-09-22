#!/bin/sh
#
# xray-vless-reality-ss2022.sh
# Install Xray and create VLESS REALITY and/or Shadowsocks 2022 inbounds.
# Supported init systems: systemd (Debian/Ubuntu) and OpenRC (Alpine).
#
# The script intentionally does not change firewall rules. Open the selected
# ports in the VPS/provider firewall separately when required.

set -eu

XRAY_BIN=/usr/local/bin/xray
XRAY_DIR=/usr/local/etc/xray
CONFIG_FILE=$XRAY_DIR/config.json
CREDENTIAL_FILE=/root/xray-credentials.txt

ENABLE_VLESS=1
ENABLE_SS=1
INTERACTIVE=0
UPGRADE=0
FORCE=0
VLESS_PORT=443
SS_PORT=8388
LISTEN_ADDR=::
LISTEN_EXPLICIT=0
IP_MODE=dual
DOMAIN_STRATEGY=UseIPv6v4
REALITY_TARGET=www.apple.com:443
SERVER_NAME=
SERVER_ADDRESS=
SS_METHOD=2022-blake3-aes-256-gcm

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
  xray-vless-reality-ss2022.sh [选项]

功能:
  安装/升级 Xray，并生成 VLESS REALITY 和 Shadowsocks 2022 入站。
  默认同时创建 VLESS 443 和 SS2022 8388。

选项:
  --vless-port PORT       VLESS REALITY 端口，默认 443
  --ss-port PORT          SS2022 端口，默认 8388
  --target HOST:PORT      REALITY 伪装目标，默认 www.apple.com:443
  --server-name NAME      REALITY SNI，默认从 --target 推导
  --server-address HOST   输出客户端链接使用的服务器地址
  --listen ADDRESS        监听地址，默认 ::
  --ip-mode MODE          IP 模式：dual、ipv4 或 ipv6，默认 dual
  --ss-method METHOD      SS2022 加密，默认 2022-blake3-aes-256-gcm
  --interactive           交互填写域名、端口、加密方式和 IP 模式
  --only-vless            只创建 VLESS REALITY
  --only-ss               只创建 Shadowsocks 2022
  --upgrade               重新执行官方 Xray 安装脚本
  --force                 允许覆盖现有配置（仍会先备份）
  -h, --help              显示帮助

示例:
  sh xray-vless-reality-ss2022.sh --server-address 2001:db8::1
  sh xray-vless-reality-ss2022.sh --vless-port 52011 --ss-port 8388
  sh xray-vless-reality-ss2022.sh --only-vless --target www.apple.com:443
EOF
}

is_port() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ "$1" -ge 1 ] 2>/dev/null && [ "$1" -le 65535 ] 2>/dev/null
}

is_safe_json_value() {
    # The accepted values are hostnames/addresses, not arbitrary JSON.
    case "$1" in
        *'"'*|*'\'*) return 1 ;;
    esac
    return 0
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
}

install_dependencies() {
    if [ "$OS" = alpine ]; then
        apk add --no-cache curl tar openssl ca-certificates >/dev/null
    else
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -y -qq curl tar openssl ca-certificates >/dev/null
    fi
}

install_xray() {
    if [ -x "$XRAY_BIN" ] && [ "$UPGRADE" -eq 0 ]; then
        info "检测到 Xray: $XRAY_BIN（跳过安装，使用 --upgrade 可升级）"
        return
    fi

    tmp_dir=$(mktemp -d)
    trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM
    if [ "$OS" = alpine ]; then
        info "使用 XTLS 官方 Alpine/OpenRC 安装脚本安装 Xray"
        curl -fsSL --retry 3 \
            https://github.com/XTLS/Xray-install/raw/main/alpinelinux/install-release.sh \
            -o "$tmp_dir/install-release.sh"
        sh "$tmp_dir/install-release.sh"
    else
        info "使用 XTLS 官方 systemd 安装脚本安装 Xray"
        curl -fsSL --retry 3 \
            https://github.com/XTLS/Xray-install/raw/main/install-release.sh \
            -o "$tmp_dir/install-release.sh"
        bash "$tmp_dir/install-release.sh" install
    fi
    [ -x "$XRAY_BIN" ] || die "Xray 安装后没有找到 $XRAY_BIN"
}

generate_uuid() {
    if [ -r /proc/sys/kernel/random/uuid ]; then
        cat /proc/sys/kernel/random/uuid
    elif command -v uuidgen >/dev/null 2>&1; then
        uuidgen
    else
        openssl rand -hex 16 | awk '{printf "%s-%s-%s-%s-%s\n", substr($0,1,8),substr($0,9,4),substr($0,13,4),substr($0,17,4),substr($0,21,12)}'
    fi
}

generate_reality_keys() {
    key_output=$($XRAY_BIN x25519 2>/dev/null) || die "无法用 Xray 生成 Reality 密钥。"
    REALITY_PRIVATE_KEY=$(printf '%s\n' "$key_output" | awk -F': *' 'tolower($1) ~ /private/ {print $2; exit}')
    REALITY_PUBLIC_KEY=$(printf '%s\n' "$key_output" | awk -F': *' 'tolower($1) ~ /password/ {print $2; exit}')
    [ -n "$REALITY_PRIVATE_KEY" ] || die "无法解析 Reality private key。"
    [ -n "$REALITY_PUBLIC_KEY" ] || die "无法解析 Reality public key。"
}

restart_service() {
    if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
        systemctl daemon-reload
        systemctl enable xray >/dev/null
        systemctl restart xray
    elif command -v rc-service >/dev/null 2>&1; then
        rc-update add xray default >/dev/null 2>&1 || true
        rc-service xray restart
    else
        die "找不到 systemd 或 OpenRC。"
    fi
}

service_status() {
    if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
        systemctl --no-pager --full status xray || true
    elif command -v rc-service >/dev/null 2>&1; then
        rc-service xray status || true
    fi
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --vless-port) [ "$#" -ge 2 ] || die "$1 需要参数"; VLESS_PORT=$2; shift 2 ;;
            --ss-port) [ "$#" -ge 2 ] || die "$1 需要参数"; SS_PORT=$2; shift 2 ;;
            --target) [ "$#" -ge 2 ] || die "$1 需要参数"; REALITY_TARGET=$2; shift 2 ;;
            --server-name) [ "$#" -ge 2 ] || die "$1 需要参数"; SERVER_NAME=$2; shift 2 ;;
            --server-address) [ "$#" -ge 2 ] || die "$1 需要参数"; SERVER_ADDRESS=$2; shift 2 ;;
            --listen) [ "$#" -ge 2 ] || die "$1 需要参数"; LISTEN_ADDR=$2; LISTEN_EXPLICIT=1; shift 2 ;;
            --ip-mode) [ "$#" -ge 2 ] || die "$1 需要参数"; IP_MODE=$2; shift 2 ;;
            --ss-method) [ "$#" -ge 2 ] || die "$1 需要参数"; SS_METHOD=$2; shift 2 ;;
            --interactive) INTERACTIVE=1; shift ;;
            --only-vless) ENABLE_VLESS=1; ENABLE_SS=0; shift ;;
            --only-ss) ENABLE_VLESS=0; ENABLE_SS=1; shift ;;
            --upgrade) UPGRADE=1; shift ;;
            --force) FORCE=1; shift ;;
            -h|--help) usage; exit 0 ;;
            *) die "未知参数: $1（使用 --help 查看帮助）" ;;
        esac
    done
}

prompt_input() {
    prompt_text=$1
    default_value=${2:-}
    answer=
    if [ -r /dev/tty ] && [ -w /dev/tty ]; then
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
    else
        die "交互模式需要可用的终端。"
    fi
    if [ -z "$answer" ]; then
        answer=$default_value
    fi
    printf '%s' "$answer"
}

choose_ss_method() {
    if [ "$ENABLE_SS" -eq 0 ]; then
        return
    fi
    choice=
    while :; do
        printf '%s\n' \
            'SS2022 加密方式:' \
            '  1) 2022-blake3-aes-128-gcm' \
            '  2) 2022-blake3-aes-256-gcm（推荐）' \
            '  3) 2022-blake3-chacha20-poly1305' \
            '请选择 [2]: ' > /dev/tty
        if IFS= read -r choice < /dev/tty; then
            :
        else
            choice=2
        fi
        case "$choice" in
            ''|2) SS_METHOD=2022-blake3-aes-256-gcm; return ;;
            1) SS_METHOD=2022-blake3-aes-128-gcm; return ;;
            3) SS_METHOD=2022-blake3-chacha20-poly1305; return ;;
            2022-blake3-aes-128-gcm|2022-blake3-aes-256-gcm|2022-blake3-chacha20-poly1305)
                SS_METHOD=$choice
                return
                ;;
            *) printf '%s\n' '请输入 1、2、3 或完整加密名称。' > /dev/tty ;;
        esac
    done
}

choose_ip_mode() {
    choice=$(prompt_input 'IP 模式（1=双栈IPv6优先，2=仅IPv4，3=仅IPv6）' '')
    case "$choice" in
        ''|1|dual) IP_MODE=dual ;;
        2|ipv4) IP_MODE=ipv4 ;;
        3|ipv6) IP_MODE=ipv6 ;;
        *) die "IP 模式只能选择 1、2、3、dual、ipv4 或 ipv6。" ;;
    esac
}

interactive_setup() {
    [ "$INTERACTIVE" -eq 1 ] || return
    [ -r /dev/tty ] && [ -w /dev/tty ] || die "交互模式需要可用的终端。"
    printf '%s\n' '' '=== Xray VLESS Reality + SS2022 配置 ===' > /dev/tty
    SERVER_ADDRESS=$(prompt_input '服务器连接域名或 IP（用于生成客户端参数）' "$SERVER_ADDRESS")
    if [ "$ENABLE_VLESS" -eq 1 ]; then
        VLESS_PORT=$(prompt_input 'VLESS Reality 端口' "$VLESS_PORT")
        REALITY_TARGET=$(prompt_input 'Reality 伪装目标（域名或 HOST:PORT）' "$REALITY_TARGET")
        if [ -z "$SERVER_NAME" ]; then
            SERVER_NAME=$(prompt_input 'Reality SNI（留空自动使用伪装目标域名）' '')
        else
            SERVER_NAME=$(prompt_input 'Reality SNI' "$SERVER_NAME")
        fi
    fi
    if [ "$ENABLE_SS" -eq 1 ]; then
        SS_PORT=$(prompt_input 'Shadowsocks 2022 端口' "$SS_PORT")
        choose_ss_method
    fi
    choose_ip_mode
    printf '%s\n' '============================================' > /dev/tty
}

apply_ip_mode() {
    case "$IP_MODE" in
        dual)
            [ "$LISTEN_EXPLICIT" -eq 1 ] || LISTEN_ADDR=::
            DOMAIN_STRATEGY=UseIPv6v4
            ;;
        ipv4)
            [ "$LISTEN_EXPLICIT" -eq 1 ] || LISTEN_ADDR=0.0.0.0
            DOMAIN_STRATEGY=UseIPv4
            ;;
        ipv6)
            [ "$LISTEN_EXPLICIT" -eq 1 ] || LISTEN_ADDR=::
            DOMAIN_STRATEGY=UseIPv6
            ;;
        *) die "IP 模式只能是 dual、ipv4 或 ipv6。" ;;
    esac
}

validate_args() {
    apply_ip_mode
    case "$REALITY_TARGET" in
        *:*) ;;
        *) REALITY_TARGET=$REALITY_TARGET:443 ;;
    esac

    [ "$ENABLE_VLESS" -eq 1 ] || [ "$ENABLE_SS" -eq 1 ] || die "至少启用一种协议。"
    [ "$ENABLE_VLESS" -eq 0 ] || is_port "$VLESS_PORT" || die "VLESS 端口无效: $VLESS_PORT"
    [ "$ENABLE_SS" -eq 0 ] || is_port "$SS_PORT" || die "SS 端口无效: $SS_PORT"
    if [ "$ENABLE_VLESS" -eq 1 ] && [ "$ENABLE_SS" -eq 1 ] && [ "$VLESS_PORT" = "$SS_PORT" ]; then
        die "VLESS 和 SS2022 不能使用同一个端口。"
    fi
    is_safe_json_value "$REALITY_TARGET" || die "--target 包含不安全字符。"
    [ -z "$SERVER_NAME" ] || is_safe_json_value "$SERVER_NAME" || die "--server-name 包含不安全字符。"
    is_safe_json_value "$LISTEN_ADDR" || die "--listen 包含不安全字符。"
    case "$SS_METHOD" in
        2022-blake3-aes-128-gcm|2022-blake3-aes-256-gcm|2022-blake3-chacha20-poly1305) ;;
        *) die "只允许 SS2022 加密方法: 2022-blake3-aes-128-gcm、2022-blake3-aes-256-gcm、2022-blake3-chacha20-poly1305" ;;
    esac
}

build_config() {
    config_tmp="$XRAY_DIR/config.json.new.$$"
    mkdir -p "$XRAY_DIR"

    if [ -z "$SERVER_NAME" ]; then
        case "$REALITY_TARGET" in
            \[*\]:*) SERVER_NAME=${REALITY_TARGET#\[}; SERVER_NAME=${SERVER_NAME%%\]*} ;;
            *:*) SERVER_NAME=${REALITY_TARGET%:*} ;;
            *) SERVER_NAME=$REALITY_TARGET ;;
        esac
    fi
    [ -n "$SERVER_NAME" ] || die "无法从 --target 推导 server name，请显式指定 --server-name。"

    VLESS_UUID=
    SS_PASSWORD=
    SHORT_ID=
    if [ "$ENABLE_VLESS" -eq 1 ]; then
        VLESS_UUID=$(generate_uuid)
        SHORT_ID=$(openssl rand -hex 8 | tr -d '\n')
        generate_reality_keys
    fi
    if [ "$ENABLE_SS" -eq 1 ]; then
        case "$SS_METHOD" in
            2022-blake3-aes-128-gcm) SS_PASSWORD=$(openssl rand -base64 16 | tr -d '\n') ;;
            *) SS_PASSWORD=$(openssl rand -base64 32 | tr -d '\n') ;;
        esac
    fi

    inbounds=
    if [ "$ENABLE_VLESS" -eq 1 ]; then
        inbounds=$(cat <<EOF
    {
      "tag": "vless-reality-in",
      "listen": "$LISTEN_ADDR",
      "port": $VLESS_PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {"id": "$VLESS_UUID", "flow": "xtls-rprx-vision", "email": "vless-reality"}
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "raw",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "target": "$REALITY_TARGET",
          "xver": 0,
          "serverNames": ["$SERVER_NAME"],
          "privateKey": "$REALITY_PRIVATE_KEY",
          "shortIds": ["$SHORT_ID"]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    }
EOF
)
    fi
    if [ "$ENABLE_SS" -eq 1 ]; then
        ss_block=$(cat <<EOF
    {
      "tag": "ss2022-in",
      "listen": "$LISTEN_ADDR",
      "port": $SS_PORT,
      "protocol": "shadowsocks",
      "settings": {
        "method": "$SS_METHOD",
        "password": "$SS_PASSWORD",
        "network": "tcp,udp"
      }
    }
EOF
        )
        if [ -n "$inbounds" ]; then
            inbounds=$(printf '%s,\n%s' "$inbounds" "$ss_block")
        else
            inbounds=$ss_block
        fi
    fi

    cat > "$config_tmp" <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [
$inbounds
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {"domainStrategy": "$DOMAIN_STRATEGY"}
    },
    {"tag": "block", "protocol": "blackhole"}
  ]
}
EOF

    info "检查 Xray 配置"
    "$XRAY_BIN" run -test -config "$config_tmp"

    backup_file=
    if [ -f "$CONFIG_FILE" ]; then
        backup_file="$CONFIG_FILE.bak.$(date +%Y%m%d%H%M%S)"
        cp -p "$CONFIG_FILE" "$backup_file"
        if [ "$FORCE" -ne 1 ]; then
            info "已有配置，已备份为 $backup_file；使用 --force 确认覆盖。"
            rm -f "$config_tmp"
            exit 1
        fi
    fi
    mv "$config_tmp" "$CONFIG_FILE"
    chmod 644 "$CONFIG_FILE"

    if ! restart_service; then
        if [ -n "$backup_file" ] && [ -f "$backup_file" ]; then
            cp -p "$backup_file" "$CONFIG_FILE"
            restart_service || true
        fi
        die "Xray 启动失败，配置已尝试回滚。"
    fi
}

write_credentials() {
    server_address=${SERVER_ADDRESS:-YOUR_SERVER_IP_OR_DOMAIN}
    case "$server_address" in
        *:*) client_host="[$server_address]" ;;
        *) client_host="$server_address" ;;
    esac
    mkdir -p "$(dirname "$CREDENTIAL_FILE")"
    umask 077
    {
        echo "# Xray generated credentials"
        echo "# 生成时间: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        echo
        if [ "$ENABLE_VLESS" -eq 1 ]; then
            echo "[VLESS REALITY]"
            echo "address=$server_address"
            echo "ipMode=$IP_MODE"
            echo "port=$VLESS_PORT"
            echo "uuid=$VLESS_UUID"
            echo "flow=xtls-rprx-vision"
            echo "security=reality"
            echo "sni=$SERVER_NAME"
            echo "fingerprint=chrome"
            echo "publicKey=$REALITY_PUBLIC_KEY"
            echo "shortId=$SHORT_ID"
            echo "type=tcp"
            echo "vless://$VLESS_UUID@$client_host:$VLESS_PORT?encryption=none&security=reality&sni=$SERVER_NAME&fp=chrome&pbk=$REALITY_PUBLIC_KEY&sid=$SHORT_ID&type=tcp&flow=xtls-rprx-vision#vless-reality"
            echo "serverPrivateKey=$REALITY_PRIVATE_KEY"
            echo
        fi
        if [ "$ENABLE_SS" -eq 1 ]; then
            echo "[Shadowsocks 2022]"
            echo "address=$server_address"
            echo "ipMode=$IP_MODE"
            echo "port=$SS_PORT"
            echo "method=$SS_METHOD"
            echo "password=$SS_PASSWORD"
            echo
        fi
    } > "$CREDENTIAL_FILE"
    chmod 600 "$CREDENTIAL_FILE"
}

main() {
    if [ "$#" -eq 0 ]; then
        if [ -r /dev/tty ] && [ -w /dev/tty ]; then
            INTERACTIVE=1
        else
            usage
            echo
            echo "未提供参数，将使用默认值创建 VLESS REALITY + SS2022。"
        fi
    fi
    parse_args "$@"
    interactive_setup
    validate_args
    require_root
    detect_os
    install_dependencies
    install_xray
    build_config
    write_credentials
    echo
    info "完成。"
    echo "配置文件: $CONFIG_FILE"
    echo "客户端参数: $CREDENTIAL_FILE"
    echo "查看状态: $( [ "$OS" = alpine ] && echo 'rc-service xray status' || echo 'systemctl status xray' )"
    echo "查看日志: tail -f /var/log/xray/{access,error}.log"
    echo
    service_status
}

main "$@"
