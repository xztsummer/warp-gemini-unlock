#!/bin/bash
# Cloudflare 官方 MASQUE + sing-box Google/Gemini 精准分流安装器
#
# 直接运行进入交互菜单；自动化场景也可使用子命令：
#   sudo bash warp-geimini-masque.sh install          # 安装/修复并接入 sing-box
#   sudo bash warp-geimini-masque.sh refresh          # 保留注册，重连刷新 MASQUE 出口并验收
#   sudo bash warp-geimini-masque.sh test             # 严格测试现有 MASQUE 代理
#   sudo bash warp-geimini-masque.sh status           # 查看服务、模式与分流状态
#   sudo bash warp-geimini-masque.sh integrate        # 仅修复 sing-box 接入
#   sudo bash warp-geimini-masque.sh restore [目录]   # 恢复指定或交互选择的备份
#   sudo bash warp-geimini-masque.sh connect|disconnect
#
# 可选环境变量：
#   WARP_PROXY_PORT=40000
#   WARP_MAX_RETRIES=10
#   SINGBOX_CONFIG=/etc/s-box/sb.json
#   WARP_ALLOW_RECONFIGURE_EXISTING=1   # 允许把已有官方 WARP 客户端切换为本地代理模式

set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MODE="${1:-menu}"
MODE_ARG="${2:-}"
WARP_PROXY_PORT="${WARP_PROXY_PORT:-40000}"
WARP_MAX_RETRIES="${WARP_MAX_RETRIES:-10}"
SINGBOX_CONFIG="${SINGBOX_CONFIG:-}"
WARP_ALLOW_RECONFIGURE_EXISTING="${WARP_ALLOW_RECONFIGURE_EXISTING:-0}"
BACKUP_DIR=""

# 只把 Google 搜索/基础服务与 Google AI 交给 MASQUE。根域名规则会覆盖其子域名。

TARGET_DOMAINS_JSON='[
  "google.com",
  "google.co.jp",
  "google.com.hk",
  "google.com.tw",
  "google.cn",
  "googleapis.com",
  "googleusercontent.com",
  "gstatic.com",
  "1e100.net",
  "google-analytics.com",
  "googletagmanager.com",
  "goo.gl",
  "google.dev",
  "web.dev",
  "chrome.com",
  "antigravity.google",
  "deepmind.com",
  "deepmind.google",
  "notebooklm.google",
  "generativeai.google"
]'

log_info() { echo -e "${CYAN}$*${NC}"; }
log_ok() { echo -e "${GREEN}✓ $*${NC}"; }
log_warn() { echo -e "${YELLOW}⚠ $*${NC}"; }
log_error() { echo -e "${RED}✗ $*${NC}" >&2; }

# ---------------------------------------------------------
# 基础校验与依赖
# ---------------------------------------------------------

require_root() {
    if [ "${EUID:-$(id -u)}" -ne 0 ]; then
        log_error "请使用 root 权限运行。"
        exit 1
    fi
}

validate_options() {
    case "$WARP_PROXY_PORT" in
        ''|*[!0-9]*) log_error "WARP_PROXY_PORT 必须是数字。"; exit 1 ;;
    esac
    if [ "$WARP_PROXY_PORT" -lt 1024 ] || [ "$WARP_PROXY_PORT" -gt 65535 ]; then
        log_error "WARP_PROXY_PORT 必须位于 1024-65535。"
        exit 1
    fi
    case "$WARP_MAX_RETRIES" in
        ''|*[!0-9]*) log_error "WARP_MAX_RETRIES 必须是数字。"; exit 1 ;;
    esac
    if [ "$WARP_MAX_RETRIES" -lt 1 ] || [ "$WARP_MAX_RETRIES" -gt 30 ]; then
        log_error "WARP_MAX_RETRIES 必须位于 1-30。"
        exit 1
    fi
}

warp_cli() {
    warp-cli --accept-tos --no-ansi "$@"
}

# 安装脚本自身依赖；不安装或修改 sing-box。
install_base_dependencies() {
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -y >/dev/null 2>&1 || return 1
        DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl gnupg jq lsb-release >/dev/null 2>&1 || return 1
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y ca-certificates curl gnupg2 jq >/dev/null 2>&1 || return 1
    elif command -v yum >/dev/null 2>&1; then
        yum install -y ca-certificates curl gnupg2 jq >/dev/null 2>&1 || return 1
    else
        log_error "仅支持 APT、DNF 或 YUM 系统。"
        exit 1
    fi
    command -v jq >/dev/null 2>&1 && command -v curl >/dev/null 2>&1
}

install_cloudflare_warp() {
    if command -v warp-cli >/dev/null 2>&1; then
        log_ok "已检测到 Cloudflare 官方 WARP 客户端。"
        return 0
    fi

    log_info "正在安装 Cloudflare 官方 WARP 客户端..."
    if command -v apt-get >/dev/null 2>&1; then
        local codename key_tmp
        codename=$(lsb_release -cs 2>/dev/null || awk -F= '/^VERSION_CODENAME=/{print $2}' /etc/os-release)
        if [ -z "$codename" ]; then
            log_error "无法识别 Debian/Ubuntu 发行版代号。"
            return 1
        fi
        key_tmp=$(mktemp /tmp/cloudflare-warp-key.XXXXXX)
        if ! curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg -o "$key_tmp"; then
            rm -f "$key_tmp"
            log_error "下载 Cloudflare 软件源公钥失败。"
            return 1
        fi
        gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg "$key_tmp"
        rm -f "$key_tmp"
        printf 'deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ %s main\n' "$codename" > /etc/apt/sources.list.d/cloudflare-client.list
        apt-get update -y >/dev/null 2>&1
        DEBIAN_FRONTEND=noninteractive apt-get install -y cloudflare-warp >/dev/null 2>&1
    else
        rpm --import https://pkg.cloudflareclient.com/pubkey.gpg >/dev/null 2>&1 || true
        curl -fsSL https://pkg.cloudflareclient.com/cloudflare-warp-ascii.repo -o /etc/yum.repos.d/cloudflare-warp.repo
        if command -v dnf >/dev/null 2>&1; then
            dnf install -y cloudflare-warp >/dev/null 2>&1
        else
            yum install -y cloudflare-warp >/dev/null 2>&1
        fi
    fi

    if ! command -v warp-cli >/dev/null 2>&1; then
        log_error "Cloudflare WARP 客户端安装失败。"
        return 1
    fi
    systemctl enable --now warp-svc >/dev/null 2>&1 || true
    log_ok "Cloudflare WARP 客户端安装完成。"
}

# ---------------------------------------------------------
# sing-box 发现、备份与恢复材料
# ---------------------------------------------------------

# 优先使用显式路径，否则探测常见路径和 systemd ExecStart。
find_singbox_config() {
    if [ -n "$SINGBOX_CONFIG" ] && [ -f "$SINGBOX_CONFIG" ]; then
        return 0
    fi

    local candidate
    for candidate in /etc/s-box/sb.json /etc/sing-box/config.json /usr/local/etc/sing-box/config.json; do
        if [ -f "$candidate" ]; then
            SINGBOX_CONFIG="$candidate"
            return 0
        fi
    done

    if systemctl cat sing-box.service >/dev/null 2>&1; then
        candidate=$(systemctl show sing-box.service -p ExecStart --value 2>/dev/null | sed -nE 's/.* (\-c|--config) ([^ ;}]+).*/\2/p' | head -n 1)
        if [ -n "$candidate" ] && [ -f "$candidate" ]; then
            SINGBOX_CONFIG="$candidate"
            return 0
        fi
    fi
    return 1
}

find_singbox_binary() {
    local candidate
    if command -v sing-box >/dev/null 2>&1; then
        command -v sing-box
        return 0
    fi
    for candidate in /etc/s-box/sing-box /usr/local/bin/sing-box /usr/bin/sing-box; do
        if [ -x "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

create_backup() {
    # 每次变更前保存官方 WARP 状态和 sing-box 配置，并生成独立 restore.sh。
    BACKUP_DIR=$(mktemp -d "/root/warp-google-masque-backup-$(date -u +%Y%m%dT%H%M%SZ).XXXXXX") || return 1
    umask 077
    chmod 700 "$BACKUP_DIR"

    if [ -d /var/lib/cloudflare-warp ]; then
        systemctl stop warp-svc >/dev/null 2>&1 || true
        cp -a /var/lib/cloudflare-warp "$BACKUP_DIR/cloudflare-warp-state"
        systemctl start warp-svc >/dev/null 2>&1 || true
        # warp-svc 启动后需要短暂时间重新载入注册状态，避免随后的检测产生假阴性。
        sleep 2
    fi
    if find_singbox_config; then
        cp -a "$SINGBOX_CONFIG" "$BACKUP_DIR/sing-box-config.json"
        printf '%s\n' "$SINGBOX_CONFIG" > "$BACKUP_DIR/sing-box-config.path"
    fi
    # v2 备份的 restore.sh 会验证 WARP 重连，并在失败时恢复操作前状态。
    printf '2\n' > "$BACKUP_DIR/format-version"
    printf '%s\n' "$WARP_PROXY_PORT" > "$BACKUP_DIR/proxy-port"
    cat > "$BACKUP_DIR/restore.sh" <<'RESTORE_EOF'
#!/bin/bash
set -u
BACKUP_DIR=$(cd "$(dirname "$0")" && pwd)
PROXY_PORT=$(head -n 1 "$BACKUP_DIR/proxy-port" 2>/dev/null || echo 40000)
ARCHIVE="/var/lib/cloudflare-warp.before-restore-$(date -u +%Y%m%dT%H%M%SZ).$$"

if [ -d "$BACKUP_DIR/cloudflare-warp-state" ]; then
    if [ -e "$ARCHIVE" ]; then echo "Restore archive already exists: $ARCHIVE" >&2; exit 1; fi
    systemctl stop warp-svc.service || exit 1
    if [ -d /var/lib/cloudflare-warp ]; then
        mv /var/lib/cloudflare-warp "$ARCHIVE" || exit 1
    fi
    cp -a "$BACKUP_DIR/cloudflare-warp-state" /var/lib/cloudflare-warp || exit 1
    systemctl start warp-svc.service || exit 1

    # 旧注册可能已在 Cloudflare 服务端失效；实际连通前不宣称恢复成功。
    if [ -s "$BACKUP_DIR/cloudflare-warp-state/reg.json" ]; then
        warp-cli --accept-tos --no-ansi connect >/dev/null 2>&1 || true
        RESTORED_WARP=0
        for _attempt in 1 2 3 4 5 6; do
            TRACE=$(curl -sS --socks5-hostname "127.0.0.1:$PROXY_PORT" --max-time 5 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null || true)
            if echo "$TRACE" | grep -q '^warp=on$'; then RESTORED_WARP=1; break; fi
            sleep 2
        done
        if [ "$RESTORED_WARP" -ne 1 ]; then
            systemctl stop warp-svc.service >/dev/null 2>&1 || true
            mv /var/lib/cloudflare-warp "${ARCHIVE}.failed" 2>/dev/null || true
            if [ -d "$ARCHIVE" ]; then
                mv "$ARCHIVE" /var/lib/cloudflare-warp
                systemctl start warp-svc.service >/dev/null 2>&1 || true
                warp-cli --accept-tos --no-ansi connect >/dev/null 2>&1 || true
            fi
            echo "Restore failed: saved WARP registration could not reconnect. Previous state was retained." >&2
            exit 1
        fi
    fi
fi

if [ -f "$BACKUP_DIR/sing-box-config.json" ] && [ -f "$BACKUP_DIR/sing-box-config.path" ]; then
    SINGBOX_PATH=$(head -n 1 "$BACKUP_DIR/sing-box-config.path")
    if [ -n "$SINGBOX_PATH" ]; then
        CURRENT_SINGBOX="$BACKUP_DIR/sing-box-before-restore-$(date -u +%Y%m%dT%H%M%SZ).$$.json"
        if [ -f "$SINGBOX_PATH" ]; then cp -a "$SINGBOX_PATH" "$CURRENT_SINGBOX"; fi
        cp -a "$BACKUP_DIR/sing-box-config.json" "$SINGBOX_PATH" || exit 1
        chmod 600 "$SINGBOX_PATH"
        if ! systemctl restart sing-box.service; then
            if [ -f "$CURRENT_SINGBOX" ]; then
                cp -a "$CURRENT_SINGBOX" "$SINGBOX_PATH"
                systemctl restart sing-box.service >/dev/null 2>&1 || true
            fi
            echo "Restore failed: sing-box did not start; previous config was retained." >&2
            exit 1
        fi
    fi
fi

echo "Restore completed from $BACKUP_DIR"
RESTORE_EOF
    chmod 700 "$BACKUP_DIR/restore.sh"
    log_ok "已创建备份：$BACKUP_DIR"
}

# ---------------------------------------------------------
# MASQUE 连接与严格验收
# ---------------------------------------------------------

# 等待 warp-svc 进入 Connected，且本地 SOCKS5 端口开始监听。
wait_for_warp_proxy() {
    local i status
    for i in $(seq 1 10); do
        status=$(warp_cli status 2>/dev/null || true)
        if echo "$status" | grep -q 'Connected' && ss -lnt 2>/dev/null | grep -q "127.0.0.1:${WARP_PROXY_PORT}"; then
            return 0
        fi
        sleep 2
    done
    return 1
}

configure_masque_proxy() {
    warp_cli tunnel protocol set MASQUE >/dev/null 2>&1 || return 1
    warp_cli mode proxy >/dev/null 2>&1 || return 1
    warp_cli proxy port "$WARP_PROXY_PORT" >/dev/null 2>&1 || return 1
    warp_cli connect >/dev/null 2>&1 || return 1
    wait_for_warp_proxy
}

# probe_proxy <port>：必须确认流量确实走 WARP，且 Google/Gemini/AI Studio 全部通过。
probe_proxy() {
    local proxy_port="$1" workdir trace exit_ip cf_loc warp_status ip_family
    local google_result google_http google_url google_geo google_sorry google_hk
    local gemini_http gemini_block ai_http ai_block
    workdir=$(mktemp -d /tmp/warp-google-probe.XXXXXX)
    chmod 700 "$workdir"

    trace=$(curl -sS --socks5-hostname "127.0.0.1:${proxy_port}" --max-time 15 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null || true)
    exit_ip=$(echo "$trace" | awk -F= '$1=="ip"{print $2}')
    cf_loc=$(echo "$trace" | awk -F= '$1=="loc"{print $2}')
    warp_status=$(echo "$trace" | awk -F= '$1=="warp"{print $2}')
    ip_family=4
    echo "$exit_ip" | grep -q ':' && ip_family=6

    google_result=$(curl -sSL --socks5-hostname "127.0.0.1:${proxy_port}" --max-time 20 \
      -o "$workdir/google.html" -w '%{http_code}\t%{url_effective}' \
      -H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36' \
      -H 'Accept-Language: en-US,en' https://www.google.com 2>/dev/null || true)
    google_http=$(echo "$google_result" | cut -f1)
    google_url=$(echo "$google_result" | cut -f2-)
    google_geo=$(grep -oP '\[1,null,null,\d+,\d+,"\K[A-Z]{3}' "$workdir/google.html" 2>/dev/null | head -n 1)
    [ -z "$google_geo" ] && google_geo=$(grep -oP '2,1,200,"\K[A-Z]{3}' "$workdir/google.html" 2>/dev/null | head -n 1)
    google_sorry=0
    google_hk=0
    echo "$google_url" | grep -q '/sorry/' && google_sorry=1
    echo "$google_url" | grep -qi 'google\.com\.hk' && google_hk=1

    gemini_http=$(curl -sSL --socks5-hostname "127.0.0.1:${proxy_port}" --max-time 25 \
      -o "$workdir/gemini.html" -w '%{http_code}' \
      -H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36' \
      -H 'Accept-Language: en-US,en' https://gemini.google.com/app 2>/dev/null || true)
    gemini_block=0
    grep -qiE 'not supported in your country|country_unavailable|not available in your region|isn.t currently supported in your country|BardErrorInfo[^0-9]*1060' "$workdir/gemini.html" 2>/dev/null && gemini_block=1

    ai_http=$(curl -sSL --socks5-hostname "127.0.0.1:${proxy_port}" --max-time 25 \
      -o "$workdir/aistudio.html" -w '%{http_code}' \
      -H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36' \
      -H 'Accept-Language: en-US,en' https://aistudio.google.com/ 2>/dev/null || true)
    ai_block=0
    grep -qiE 'not supported in your country|country_unavailable|not available in your region' "$workdir/aistudio.html" 2>/dev/null && ai_block=1

    echo "出口族: IPv${ip_family} | WARP: ${warp_status:-未知} | CF: ${cf_loc:-未知} | Google: ${google_geo:-未知} | Google HTTP: ${google_http:-000} | Gemini: ${gemini_http:-000}/block=${gemini_block} | AI Studio: ${ai_http:-000}/block=${ai_block}"
    rm -rf "$workdir"

    [ -n "$exit_ip" ] && [ "$warp_status" = "on" ] && [ "$google_http" = "200" ] && [ "$google_sorry" -eq 0 ] && [ "$google_hk" -eq 0 ] \
      && [ -n "$google_geo" ] && [ "$google_geo" != "CHN" ] && [ "$google_geo" != "HKG" ] \
      && [ "$gemini_http" = "200" ] && [ "$gemini_block" -eq 0 ] \
      && [ "$ai_http" = "200" ] && [ "$ai_block" -eq 0 ]
}

has_existing_registration() {
    local registration attempt max_attempts="${1:-10}"
    for attempt in $(seq 1 "$max_attempts"); do
        registration=$(warp-cli --accept-tos --json registration show 2>/dev/null || true)
        if [ -n "$registration" ] && echo "$registration" | jq -e '.id != null and .device_id != null' >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    return 1
}

# 已有注册只通过 MASQUE 断线重连刷新出口，不删除设备；首次安装才创建注册。
# require_change=1 用于强制刷新，要求新公网出口 IP 与刷新前不同。
refresh_masque_exit() {
    local require_change="${1:-0}" old_ip="${2:-}" attempt had_registration=0 new_ip trace
    if has_existing_registration; then
        had_registration=1
        if [ -z "$old_ip" ]; then
            trace=$(curl -sS --socks5-hostname "127.0.0.1:${WARP_PROXY_PORT}" --max-time 8 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null || true)
            old_ip=$(echo "$trace" | awk -F= '$1=="ip"{print $2; exit}')
        fi
    fi
    for attempt in $(seq 1 "$WARP_MAX_RETRIES"); do
        if [ "$had_registration" -eq 1 ]; then
            log_info "[MASQUE $attempt/$WARP_MAX_RETRIES] 保留现有注册，正在重连刷新出口..."
            warp_cli disconnect >/dev/null 2>&1 || true
            if ! warp_cli connect >/dev/null 2>&1 || ! wait_for_warp_proxy; then
                log_warn "重连失败，准备重试。"
                sleep 2
                continue
            fi
        else
            log_info "[MASQUE $attempt/$WARP_MAX_RETRIES] 正在注册并验收新设备..."
            if ! warp_cli registration new >/dev/null 2>&1; then
                log_warn "注册失败，准备重试。"
                sleep 2
                continue
            fi
            if ! configure_masque_proxy; then
                log_warn "MASQUE 连接未就绪，准备重试。"
                warp_cli registration delete >/dev/null 2>&1 || true
                sleep 2
                continue
            fi
        fi

        trace=$(curl -sS --socks5-hostname "127.0.0.1:${WARP_PROXY_PORT}" --max-time 8 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null || true)
        new_ip=$(echo "$trace" | awk -F= '$1=="ip"{print $2; exit}')
        if probe_proxy "$WARP_PROXY_PORT"; then
            if [ "$require_change" -eq 0 ] || [ -z "${old_ip:-}" ] || [ "$new_ip" != "$old_ip" ]; then
                if [ "$had_registration" -eq 1 ]; then
                    log_ok "找到通过严格验收的 MASQUE WARP 出口（沿用原有注册）。"
                else
                    log_ok "新注册的设备通过严格验收，已保留该出口。"
                fi
                return 0
            fi
            log_warn "出口仍是原 IP，继续尝试。"
        fi
        if [ "$had_registration" -eq 0 ]; then
            # 这里删除的仅是本轮新建且未通过验收的候选注册。
            warp_cli disconnect >/dev/null 2>&1 || true
            warp_cli registration delete >/dev/null 2>&1 || true
        fi
        sleep 2
    done

    log_error "已尝试 $WARP_MAX_RETRIES 次，仍未找到符合条件的 MASQUE 出口。"
    if [ "$had_registration" -eq 0 ] && [ -n "$BACKUP_DIR" ] && [ -x "$BACKUP_DIR/restore.sh" ]; then
        bash "$BACKUP_DIR/restore.sh" >/dev/null 2>&1 || log_warn "恢复首次安装前状态未完成，请检查 $BACKUP_DIR/restore.sh。"
    elif [ "$had_registration" -eq 1 ]; then
        warp_cli connect >/dev/null 2>&1 || true
        log_warn "原 WARP 注册仍保留；请查看随后显示的当前出口状态。"
    fi
    return 1
}

# 智能模式先验收已有注册；不通过时尝试重连取得新出口。
find_usable_masque_registration() {
    local had_registration=0
    has_existing_registration && had_registration=1

    # 先验收已有注册，避免不必要地删除用户现有官方 WARP 设备。
    if [ "$had_registration" -eq 1 ]; then
        log_info "正在验收已有 MASQUE 注册..."
        if configure_masque_proxy && probe_proxy "$WARP_PROXY_PORT"; then
            log_ok "已有 MASQUE 注册通过严格验收。"
            return 0
        fi
        log_warn "已有注册的出口未通过，准备在保留注册的前提下重连筛选。"
    fi

    refresh_masque_exit 0
}

choose_health_port() {
    local port
    for port in $(seq 18080 18120); do
        if ! ss -lnt 2>/dev/null | awk '{print $4}' | grep -qE "(^|:)${port}$"; then
            echo "$port"
            return 0
        fi
    done
    return 1
}

# 将目标域名路由写入 sing-box。修改前备份，使用临时本地 SOCKS 入口做端到端验证，
# 验证结束后删除临时入口；任何失败都恢复原 sing-box 配置。
integrate_singbox() {
    if ! find_singbox_config; then
        if systemctl is-active --quiet sing-box.service 2>/dev/null; then
            log_error "sing-box 正在运行，但无法定位它的配置文件；请通过 SINGBOX_CONFIG 指定路径。"
            return 1
        fi
        log_warn "未检测到 sing-box 配置；MASQUE SOCKS5 已可用于 127.0.0.1:${WARP_PROXY_PORT}。"
        return 0
    fi

    local singbox_bin health_port candidate clean_candidate original_mode
    singbox_bin=$(find_singbox_binary) || {
        log_error "找到 sing-box 配置，但未找到 sing-box 可执行文件。"
        return 1
    }
    health_port=$(choose_health_port) || {
        log_error "无法分配本地健康检查端口。"
        return 1
    }
    candidate=$(mktemp /tmp/sing-box-warp.XXXXXX.json)
    clean_candidate=$(mktemp /tmp/sing-box-warp-clean.XXXXXX.json)
    original_mode=$(stat -c '%a' "$SINGBOX_CONFIG" 2>/dev/null || echo 600)
    log_info "使用 sing-box 配置 $SINGBOX_CONFIG（可执行文件 $singbox_bin，健康检查端口 $health_port）"

    # 候选配置额外路由 Cloudflare trace，确认请求确实走到 WARP。
    jq --argjson domains "$TARGET_DOMAINS_JSON" --argjson proxy_port "$WARP_PROXY_PORT" --argjson health_port "$health_port" '
      .outbounds = (((.outbounds // []) | map(select(.tag != "warp-masque"))) + [
        {"type":"socks","tag":"warp-masque","server":"127.0.0.1","server_port":$proxy_port,"version":"5"}
      ])
      | ((.route.rules // []) | map(select(.outbound != "warp-masque"))) as $rules
      | .route.rules = (
          [$rules[] | select(.action == "sniff")] +
          [{"domain_suffix":($domains + ["www.cloudflare.com"]),"outbound":"warp-masque"}] +
          [$rules[] | select(.action != "sniff")]
        )
      | .inbounds = (((.inbounds // []) | map(select(.tag != "warp-healthcheck"))) + [
          {"type":"socks","tag":"warp-healthcheck","listen":"127.0.0.1","listen_port":$health_port}
        ])
    ' "$SINGBOX_CONFIG" > "$candidate"
    chmod "$original_mode" "$candidate"

    if ! "$singbox_bin" check -c "$candidate"; then
        rm -f "$candidate" "$clean_candidate"
        log_error "生成的 sing-box 配置未通过语法检查，未修改生产配置。"
        return 1
    fi

    cp -a "$candidate" "$SINGBOX_CONFIG"
    chmod 600 "$SINGBOX_CONFIG"
    systemctl restart sing-box.service
    sleep 3
    if ! systemctl is-active --quiet sing-box.service || ! ss -lnt 2>/dev/null | grep -q "127.0.0.1:${health_port}"; then
        cp -a "$BACKUP_DIR/sing-box-config.json" "$SINGBOX_CONFIG"
        systemctl restart sing-box.service >/dev/null 2>&1 || true
        rm -f "$candidate" "$clean_candidate"
        log_error "sing-box 临时验证入口启动失败，已恢复原配置。"
        return 1
    fi

    log_info "正在通过生产 sing-box 路由执行端到端验收..."
    if ! probe_proxy "$health_port"; then
        cp -a "$BACKUP_DIR/sing-box-config.json" "$SINGBOX_CONFIG"
        systemctl restart sing-box.service >/dev/null 2>&1 || true
        rm -f "$candidate" "$clean_candidate"
        log_error "sing-box 端到端验收失败，已恢复原配置。"
        return 1
    fi

    # 正式配置中移除临时入口和 trace 域名，仍只分流目标 Google 服务。
    jq --argjson domains "$TARGET_DOMAINS_JSON" '
      .inbounds |= map(select(.tag != "warp-healthcheck"))
      | .route.rules |= map(if .outbound == "warp-masque" then .domain_suffix = $domains else . end)
    ' "$SINGBOX_CONFIG" > "$clean_candidate"
    chmod 600 "$clean_candidate"
    if ! "$singbox_bin" check -c "$clean_candidate"; then
        cp -a "$BACKUP_DIR/sing-box-config.json" "$SINGBOX_CONFIG"
        systemctl restart sing-box.service >/dev/null 2>&1 || true
        rm -f "$candidate" "$clean_candidate"
        log_error "删除健康检查入口后的配置校验失败，已恢复原配置。"
        return 1
    fi
    mv "$clean_candidate" "$SINGBOX_CONFIG"
    chmod 600 "$SINGBOX_CONFIG"
    systemctl restart sing-box.service
    rm -f "$candidate"
    sleep 2
    if ! systemctl is-active --quiet sing-box.service; then
        cp -a "$BACKUP_DIR/sing-box-config.json" "$SINGBOX_CONFIG"
        systemctl restart sing-box.service >/dev/null 2>&1 || true
        log_error "sing-box 最终启动失败，已恢复原配置。"
        return 1
    fi

    log_ok "已将 Google 搜索/核心基础与 Google AI 域名接入 MASQUE；临时测试入口已删除。"
}

# ---------------------------------------------------------
# 用户动作：安装、刷新、测试、状态、恢复、连接管理
# ---------------------------------------------------------

# 安装/刷新共用准备：检查显式配置路径，安装脚本依赖与官方客户端。
prepare_install_environment() {
    require_root
    validate_options
    if [ -n "$SINGBOX_CONFIG" ] && [ ! -f "$SINGBOX_CONFIG" ]; then
        log_error "指定的 sing-box 配置不存在：$SINGBOX_CONFIG"
        return 1
    fi
    if ! install_base_dependencies; then
        log_error "安装 curl、jq 等基础依赖失败。"
        return 1
    fi
    install_cloudflare_warp
}

# 保护已被其他业务使用的官方客户端模式；只有显式授权才切换为本地代理。
ensure_existing_mode_is_safe() {
    if has_existing_registration; then
        local existing_mode
        existing_mode=$(warp-cli --accept-tos --json settings list 2>/dev/null | jq -r '.settings.operation_mode // "unknown"' 2>/dev/null)
        if [ "$existing_mode" != "proxy" ] && [ "$WARP_ALLOW_RECONFIGURE_EXISTING" != "1" ]; then
            log_error "当前官方 WARP 客户端处于 ${existing_mode:-unknown} 模式；切换为本地代理会影响其现有用途。"
            log_warn "确认要切换时设置 WARP_ALLOW_RECONFIGURE_EXISTING=1。"
            return 1
        fi
    fi
}

# 智能安装/修复：优先复用已通过验收的注册，再接入 sing-box。
run_install() {
    prepare_install_environment || return 1
    ensure_existing_mode_is_safe || return 1
    create_backup || return 1
    if ! find_usable_masque_registration; then
        log_error "MASQUE 出口筛选失败；未修改 sing-box。备份位于：$BACKUP_DIR"
        return 1
    fi
    if ! integrate_singbox; then
        bash "$BACKUP_DIR/restore.sh" >/dev/null 2>&1 || log_warn "自动恢复未完成，请检查 $BACKUP_DIR/restore.sh。"
        log_error "sing-box 集成失败，已尝试恢复部署前配置。备份位于：$BACKUP_DIR"
        return 1
    fi
    log_ok "部署完成。严格验收标准：Google 非 CHN/HKG，Gemini 与 AI Studio 均为 HTTP 200 且无地区限制文本。"
    echo "备份目录：$BACKUP_DIR"
}

# 强制刷新：保留官方注册，反复重连寻找不同且合格的出口 IP。
run_refresh() {
    prepare_install_environment || return 1
    ensure_existing_mode_is_safe || return 1
    local original_trace original_ip
    original_trace=$(curl -sS --socks5-hostname "127.0.0.1:${WARP_PROXY_PORT}" --max-time 8 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null || true)
    original_ip=$(echo "$original_trace" | awk -F= '$1=="ip"{print $2; exit}')
    create_backup || return 1
    if ! refresh_masque_exit 1 "$original_ip"; then
        log_error "强制刷新未找到新的合格出口，现有注册保持不变。"
        return 1
    fi
    if ! integrate_singbox; then
        bash "$BACKUP_DIR/restore.sh" >/dev/null 2>&1 || log_warn "自动恢复未完成，请检查 $BACKUP_DIR/restore.sh。"
        log_error "新出口可用，但 sing-box 接入失败；已尝试恢复刷新前状态。"
        return 1
    fi
    log_ok "WARP 出口已刷新，并通过严格验收。"
    echo "备份目录：$BACKUP_DIR"
}

# 严格测试为只读操作，不修改注册、工作模式或 sing-box。
run_test() {
    require_root
    validate_options
    if ! command -v warp-cli >/dev/null 2>&1; then
        log_error "未安装官方 Cloudflare WARP 客户端。"
        return 1
    fi
    if probe_proxy "$WARP_PROXY_PORT"; then
        log_ok "现有 MASQUE 代理通过严格验收。"
    else
        log_error "现有 MASQUE 代理未通过严格验收。"
        return 1
    fi
}

# 仅修复 sing-box 路由；要求现有 MASQUE 出口已经通过严格测试。
run_integrate() {
    require_root
    validate_options
    if ! command -v jq >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
        log_error "缺少 jq 或 curl；请先运行安装/修复。"
        return 1
    fi
    if ! command -v warp-cli >/dev/null 2>&1 || ! run_test; then
        log_error "当前 MASQUE 出口不可用，未修改 sing-box。"
        return 1
    fi
    create_backup || return 1
    if ! integrate_singbox; then
        bash "$BACKUP_DIR/restore.sh" >/dev/null 2>&1 || true
        return 1
    fi
    log_ok "sing-box 接入已修复。"
    echo "备份目录：$BACKUP_DIR"
}

# 状态探针：所有请求都经同一个本地 MASQUE SOCKS5 端口发送。
# Cloudflare trace 给出代理公网出口 IP；Google 首页给出 HTTP 状态和内部地区码。
# Google 首页并不直接回显访客 IP，因此不把代理 IP 冒充为 Google 自身确认的 IP。
probe_google_masque_status() {
    local proxy="127.0.0.1:${WARP_PROXY_PORT}" trace trace_v4 ip ip_v4 warp_flag warp_v4
    local google_file google_result google_http google_url google_geo
    trace=$(curl -sS --socks5-hostname "$proxy" --max-time 8 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null || true)
    ip=$(echo "$trace" | awk -F= '$1=="ip"{print $2; exit}')
    warp_flag=$(echo "$trace" | awk -F= '$1=="warp"{print $2; exit}')

    # 本地解析模式优先探测 IPv4；远程解析模式可得到另一个 IPv6 出口。
    trace_v4=$(curl -4 -sS --socks5 "$proxy" --max-time 8 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null || true)
    ip_v4=$(echo "$trace_v4" | awk -F= '$1=="ip"{print $2; exit}')
    warp_v4=$(echo "$trace_v4" | awk -F= '$1=="warp"{print $2; exit}')
    echo "MASQUE 公网出口（经代理探测）："
    if [ "$warp_flag" = "on" ] && [ -n "$ip" ]; then
        echo "  远程解析: $ip"
    else
        echo "  远程解析: 未取得 WARP 出口 IP"
    fi
    if [ "$warp_v4" = "on" ] && [ -n "$ip_v4" ]; then
        echo "  IPv4 探测: $ip_v4"
    else
        echo "  IPv4 探测: 未取得 WARP 出口 IP"
    fi

    google_file=$(mktemp /tmp/warp-google-status.XXXXXX) || return 1
    google_result=$(curl -sSL --socks5-hostname "$proxy" --max-time 12 -o "$google_file" \
      -w '%{http_code}|%{url_effective}' \
      -H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36' \
      -H 'Accept-Language: en-US,en' https://www.google.com 2>/dev/null || true)
    google_http=${google_result%%|*}
    google_url=${google_result#*|}
    google_geo=$(grep -oP '\[1,null,null,\d+,\d+,"\K[A-Z]{3}' "$google_file" 2>/dev/null | head -n 1)
    [ -z "$google_geo" ] && google_geo=$(grep -oP '2,1,200,"\K[A-Z]{3}' "$google_file" 2>/dev/null | head -n 1)
    rm -f "$google_file"
    echo "Google 经 MASQUE 访问: HTTP ${google_http:-000} / 内部地区 ${google_geo:-未知}"
    if [ -n "$google_url" ] && [ "$google_url" != 'https://www.google.com/' ]; then
        echo "Google 最终地址: $google_url"
    fi
}

# 只列出带有 v2 恢复验证标记的备份；旧版备份可能包含已注销设备。
list_safe_backups() {
    local item
    while IFS= read -r item; do
        [ "$(cat "$item/format-version" 2>/dev/null)" = "2" ] && echo "$item"
    done < <(find /root -maxdepth 1 -type d -name 'warp-google-masque-backup-*' -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-)
}

# 输出脱敏状态，不显示设备 ID、许可证、Token、私钥或 sing-box 凭据。
run_status() {
    require_root
    validate_options
    echo "========================================================"
    echo "Cloudflare WARP MASQUE 状态"
    echo "========================================================"
    if command -v warp-cli >/dev/null 2>&1; then
        echo "客户端版本: $(warp-cli --version 2>/dev/null | head -n 1)"
        echo "warp-svc:   $(systemctl is-active warp-svc.service 2>/dev/null || true) / $(systemctl is-enabled warp-svc.service 2>/dev/null || true)"
        echo "注册状态:   $({ has_existing_registration 1 && echo 已注册; } || echo 未注册)"
        local settings operation protocol proxy_port connection
        settings=$(warp-cli --accept-tos --json settings list 2>/dev/null || true)
        operation=$(echo "$settings" | jq -r '.settings.operation_mode // "未知"' 2>/dev/null)
        protocol=$(echo "$settings" | jq -r '.settings.warp_tunnel_protocol // "未知"' 2>/dev/null)
        proxy_port=$(echo "$settings" | jq -r '.settings.proxy_port // "未知"' 2>/dev/null)
        connection=$(warp_cli status 2>/dev/null | awk -F': ' '/Status update/{print $2; exit}')
        echo "连接状态:   ${connection:-未知}"
        echo "工作模式:   $operation / $protocol / SOCKS5 127.0.0.1:$proxy_port"
        if ss -lnt 2>/dev/null | grep -q "127.0.0.1:${WARP_PROXY_PORT}"; then echo "代理监听:   正常"; else echo "代理监听:   未监听"; fi
    else
        echo "官方客户端: 未安装"
    fi

    if find_singbox_config; then
        local outbound_count rule_count
        outbound_count=$(jq '[.outbounds[]? | select(.tag=="warp-masque")]|length' "$SINGBOX_CONFIG" 2>/dev/null || echo 0)
        rule_count=$(jq '[.route.rules[]? | select(.outbound=="warp-masque")]|length' "$SINGBOX_CONFIG" 2>/dev/null || echo 0)
        echo "sing-box:   $(systemctl is-active sing-box.service 2>/dev/null || true) / 配置 $SINGBOX_CONFIG"
        echo "精准分流:   出站 $outbound_count 条，规则 $rule_count 条"
    else
        echo "sing-box:   未检测到配置"
    fi
    if command -v curl >/dev/null 2>&1 && ss -lnt 2>/dev/null | grep -q "127.0.0.1:${WARP_PROXY_PORT}"; then
        probe_google_masque_status
    else
        echo "MASQUE 公网出口: 代理未监听，无法探测 Google 路径"
    fi
    local latest_backup
    latest_backup=$(list_safe_backups | head -n 1)
    echo "最近备份:   ${latest_backup:-无}"
    echo "========================================================"
}

# 只允许恢复本项目位于 /root 的时间戳备份。
run_restore() {
    require_root
    local selected="$MODE_ARG" resolved choice
    if [ -z "$selected" ]; then
        mapfile -t backups < <(list_safe_backups)
        if [ "${#backups[@]}" -eq 0 ]; then log_error "没有找到可恢复的 MASQUE 备份。"; return 1; fi
        if [ ! -t 0 ]; then log_error "非交互模式请指定备份目录：restore /root/warp-google-masque-backup-..."; return 1; fi
        echo "可用备份："
        local i
        for i in "${!backups[@]}"; do echo "$((i+1)). ${backups[$i]}"; done
        read -r -p "请选择备份编号 [1-${#backups[@]}]：" choice
        case "$choice" in ''|*[!0-9]*) log_error "无效编号。"; return 1 ;; esac
        if [ "$choice" -lt 1 ] || [ "$choice" -gt "${#backups[@]}" ]; then log_error "无效编号。"; return 1; fi
        selected="${backups[$((choice-1))]}"
    fi
    resolved=$(readlink -f -- "$selected" 2>/dev/null || true)
    case "$resolved" in /root/warp-google-masque-backup-*) ;; *) log_error "拒绝恢复非本项目备份目录：$selected"; return 1 ;; esac
    if [ "$(cat "$resolved/format-version" 2>/dev/null)" != "2" ]; then
        log_error "旧版备份缺少连通性校验，不能通过菜单恢复：$resolved"
        return 1
    fi
    if [ ! -x "$resolved/restore.sh" ]; then log_error "备份缺少可执行 restore.sh：$resolved"; return 1; fi
    bash "$resolved/restore.sh" || return 1
    log_ok "已从备份恢复：$resolved"
}

# 连接管理只改变在线状态，不删除注册或分流配置。
run_connect() {
    require_root
    command -v warp-cli >/dev/null 2>&1 || { log_error "未安装官方 WARP 客户端。"; return 1; }
    warp_cli connect >/dev/null 2>&1 || return 1
    if wait_for_warp_proxy; then log_ok "MASQUE 已连接。"; else log_error "连接超时。"; return 1; fi
}

run_disconnect() {
    require_root
    command -v warp-cli >/dev/null 2>&1 || { log_error "未安装官方 WARP 客户端。"; return 1; }
    warp_cli disconnect >/dev/null 2>&1 || return 1
    log_ok "MASQUE 已断开；sing-box 分流配置保留。"
}

# 安装、刷新、接入动作结束后统一展示状态；保留原动作的退出码。
run_and_report() {
    local result=0
    "$@" || result=$?
    echo
    run_status || true
    return "$result"
}

print_usage() {
    cat <<EOF
用法：sudo bash $0 [命令]
  menu                 交互式管理菜单（默认）
  install              智能安装/修复
  refresh              保留注册，重连刷新 MASQUE 出口并验收
  test                 严格测试当前出口
  status               查看脱敏状态
  integrate            仅修复 sing-box 接入
  restore [备份目录]   恢复备份
  connect              连接 MASQUE
  disconnect           断开 MASQUE
EOF
}

pause_menu() { [ -t 0 ] && read -r -p "按回车返回菜单..." _unused; }

main_menu() {
    require_root
    validate_options
    if [ ! -t 0 ]; then print_usage; return 1; fi
    local choice rc
    while true; do
        clear 2>/dev/null || true
        echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║       Cloudflare WARP MASQUE · Google/Gemini 管理       ║${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
        echo "1. 智能安装 / 修复 MASQUE 与 sing-box 分流"
        echo "2. 保留注册，刷新 MASQUE 出口并严格验收"
        echo "3. 严格测试当前 Google / Gemini / AI Studio"
        echo "4. 查看运行状态与最近备份"
        echo "5. 仅修复 sing-box 精准分流接入"
        echo "6. 从备份恢复"
        echo "7. 连接 MASQUE"
        echo "8. 断开 MASQUE"
        echo "0. 退出"
        echo
        read -r -p "请输入选项 [0-8]：" choice
        rc=0
        case "$choice" in
            1) run_and_report run_install || rc=$? ;;
            2) run_and_report run_refresh || rc=$? ;;
            3) run_test || rc=$? ;;
            4) run_status || rc=$? ;;
            5) run_and_report run_integrate || rc=$? ;;
            6) MODE_ARG=""; run_restore || rc=$? ;;
            7) run_connect || rc=$? ;;
            8) run_disconnect || rc=$? ;;
            0|'') return 0 ;;
            *) log_error "无效选项。"; rc=1 ;;
        esac
        [ "$rc" -ne 0 ] && log_warn "操作未完成（退出码 $rc）。"
        pause_menu
    done
}

case "$MODE" in
    menu) main_menu ;;
    install) run_and_report run_install ;;
    refresh) run_and_report run_refresh ;;
    test) run_test ;;
    status) run_status ;;
    integrate|repair-singbox) run_and_report run_integrate ;;
    restore) run_restore ;;
    connect) run_connect ;;
    disconnect) run_disconnect ;;
    help|-h|--help) print_usage ;;
    *) print_usage; exit 1 ;;
esac
