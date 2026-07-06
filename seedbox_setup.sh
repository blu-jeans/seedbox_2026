#!/usr/bin/env bash
#===============================================================================
#  Seedbox 一键初始化脚本 (Debian 11+ 稳定版)
#  @author  hyq
#  @version 2026-07-01
#  @usage   chmod +x seedbox_setup.sh && sudo ./seedbox_setup.sh
#
#  功能清单：
#    [1]  IPv4 优先 (gai.conf)
#    [2]  基础工具 (lrzsz unzip vim fuse curl wget git build-essential)
#    [3]  RAR 最新稳定版 (rarlab.com)
#    [4]  自定义 VIM 模版 (blu-jeans/seedbox)
#    [5]  时区设置 (Asia/Shanghai 北京时间)
#    [6]  inotify 内核限制解除
#    [7]  wondershaper 限速工具 (全局命令)
#    [8]  rclone 稳定版
#    [9]  qBittorrent-nox 4.3.9
#    [10] Python 3.12 + pip3
#    [11] 系统监控工具集 (nload iftop htop ncdu iotop)
#    [12] 硬盘 IO 基准测试 (fio)
#    [13] FileBrowser HTTP 文件下载服务 (带认证)
#    [14] Docker + Docker Compose 稳定版
#===============================================================================

set -euo pipefail

# ============================= 颜色与日志 =====================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

TOTAL_STEPS=14
CURRENT_STEP=0

# 安装结果追踪数组
declare -A RESULTS
STEP_NAMES=(
    "IPv4 优先"
    "基础工具"
    "RAR 最新稳定版"
    "自定义 VIM 模版"
    "时区 (Asia/Shanghai)"
    "inotify 内核限制"
    "wondershaper 限速"
    "rclone 稳定版"
    "qBittorrent-nox 4.3.9"
    "Python 3.12 + pip3"
    "系统监控工具集"
    "硬盘 IO 测试 (fio)"
    "FileBrowser 文件服务"
    "Docker + Compose"
)

# 日志文件
LOG_DIR="/var/log/seedbox_setup"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/setup_$(date +%Y%m%d_%H%M%S).log"

log_info()    { echo -e "${BLUE}[INFO]${NC}  $*" | tee -a "$LOG_FILE"; }
log_ok()      { echo -e "${GREEN}[  OK]${NC}  $*" | tee -a "$LOG_FILE"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*" | tee -a "$LOG_FILE"; }
log_err()     { echo -e "${RED}[FAIL]${NC}  $*" | tee -a "$LOG_FILE"; }
log_step()    {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    echo "" | tee -a "$LOG_FILE"
    echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$LOG_FILE"
    echo -e "${CYAN}${BOLD}  [${CURRENT_STEP}/${TOTAL_STEPS}] $*${NC}" | tee -a "$LOG_FILE"
    echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$LOG_FILE"
}

# 标记步骤结果：mark_result <step_index_0based> <status>
# status: OK / FAIL / SKIP
mark_result() {
    local idx=$1
    local status=$2
    RESULTS[$idx]="$status"
}

# ============================= 前置检查 =======================================

echo -e "${BOLD}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║        Seedbox 一键初始化脚本  (Debian 11+ 稳定版)         ║"
echo "║        @author hyq    @version $(date +%Y-%m-%d)              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# 必须以 root 运行
if [[ $EUID -ne 0 ]]; then
    log_err "此脚本必须以 root 权限运行！请使用: sudo $0"
    exit 1
fi

# 检测 Debian 版本
if [[ ! -f /etc/os-release ]]; then
    log_err "无法检测操作系统版本，/etc/os-release 不存在"
    exit 1
fi

source /etc/os-release

if [[ "$ID" != "debian" ]]; then
    log_err "此脚本仅支持 Debian 系统，当前系统: $ID"
    exit 1
fi

DEBIAN_VERSION="${VERSION_ID:-0}"
if [[ "$DEBIAN_VERSION" -lt 11 ]]; then
    log_err "此脚本需要 Debian 11 (Bullseye) 或更高版本，当前版本: $DEBIAN_VERSION"
    exit 1
fi

log_info "系统检测通过: Debian $DEBIAN_VERSION ($VERSION_CODENAME)"
log_info "CPU 架构: $(uname -m)"
log_info "详细日志文件: $LOG_FILE"
log_info "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"

# 检测 CPU 架构
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  ARCH_TAG="x64" ;;
    aarch64) ARCH_TAG="arm64" ;;
    *)
        log_err "不支持的 CPU 架构: $ARCH（仅支持 x86_64 / aarch64）"
        exit 1
        ;;
esac

# ============================= apt 源更新 =====================================

log_info "更新 apt 包索引..."
apt-get update -qq >> "$LOG_FILE" 2>&1 && log_ok "apt 索引更新完成" || log_warn "apt 索引更新部分失败，继续执行"

# =============================================================================
#  [1/14] IPv4 优先
# =============================================================================
log_step "配置 IPv4 优先 (gai.conf)"

GAI_CONF="/etc/gai.conf"
IPV4_RULE="precedence  ::ffff:0:0/96   100"

if grep -qF "$IPV4_RULE" "$GAI_CONF" 2>/dev/null; then
    log_warn "IPv4 优先规则已存在于 $GAI_CONF，跳过"
    mark_result 0 "SKIP"
else
    echo "$IPV4_RULE" >> "$GAI_CONF"
    if grep -qF "$IPV4_RULE" "$GAI_CONF"; then
        log_ok "IPv4 优先规则已写入 $GAI_CONF"
        mark_result 0 "OK"
    else
        log_err "写入 $GAI_CONF 失败"
        mark_result 0 "FAIL"
    fi
fi

# =============================================================================
#  [2/14] 基础工具
# =============================================================================
log_step "安装基础工具 (lrzsz unzip vim fuse curl wget git build-essential)"

BASE_PKGS="lrzsz unzip vim fuse curl wget git build-essential"
INSTALL_FAIL=0

for pkg in $BASE_PKGS; do
    if dpkg -s "$pkg" &>/dev/null; then
        log_info "  ✓ $pkg 已安装，跳过"
    else
        log_info "  → 正在安装 $pkg ..."
        if apt-get install -y -qq "$pkg" >> "$LOG_FILE" 2>&1; then
            log_ok "  ✓ $pkg 安装成功"
        else
            log_err "  ✗ $pkg 安装失败"
            INSTALL_FAIL=1
        fi
    fi
done

if [[ $INSTALL_FAIL -eq 0 ]]; then
    mark_result 1 "OK"
else
    mark_result 1 "FAIL"
fi

# =============================================================================
#  [3/14] RAR 最新稳定版
# =============================================================================
log_step "安装 RAR 最新稳定版 (rarlab.com)"

if command -v rar &>/dev/null; then
    RAR_VER=$(rar 2>&1 | head -1 || true)
    log_warn "rar 已安装: $RAR_VER，跳过"
    mark_result 2 "SKIP"
else
    TMP_RAR=$(mktemp -d)
    # 根据架构选择下载链接
    if [[ "$ARCH" == "x86_64" ]]; then
        RAR_URL="https://www.rarlab.com/rar/rarlinux-x64-710.tar.gz"
    elif [[ "$ARCH" == "aarch64" ]]; then
        RAR_URL="https://www.rarlab.com/rar/rarlinux-arm-710.tar.gz"
    fi

    log_info "下载 RAR: $RAR_URL"
    if wget -q --show-progress -O "$TMP_RAR/rar.tar.gz" "$RAR_URL" 2>> "$LOG_FILE"; then
        tar -xzf "$TMP_RAR/rar.tar.gz" -C "$TMP_RAR" >> "$LOG_FILE" 2>&1
        # 安装到 /usr/local/bin 及 /usr/local/lib
        cd "$TMP_RAR/rar"
        cp -f rar unrar /usr/local/bin/
        cp -f rarfiles.lst /etc/
        cp -f default.sfx /usr/local/lib/ 2>/dev/null || true
        chmod 755 /usr/local/bin/rar /usr/local/bin/unrar
        cd /
        rm -rf "$TMP_RAR"

        if command -v rar &>/dev/null; then
            log_ok "RAR 安装成功: $(rar 2>&1 | head -1 || echo 'installed')"
            mark_result 2 "OK"
        else
            log_err "RAR 安装后命令不可用"
            mark_result 2 "FAIL"
        fi
    else
        log_err "RAR 下载失败"
        rm -rf "$TMP_RAR"
        mark_result 2 "FAIL"
    fi
fi

# =============================================================================
#  [4/14] 自定义 VIM 模版
# =============================================================================
log_step "部署自定义 VIM 模版 (blu-jeans/seedbox)"

VIM_RAR_URL="https://github.com/blu-jeans/seedbox/raw/master/vim.rar"
TMP_VIM=$(mktemp -d)

log_info "下载 vim.rar: $VIM_RAR_URL"
if wget -q --show-progress -O "$TMP_VIM/vim.rar" "$VIM_RAR_URL" 2>> "$LOG_FILE"; then
    cd "$TMP_VIM"
    # 确保 rar/unrar 可用
    if command -v unrar &>/dev/null; then
        unrar x -o+ vim.rar >> "$LOG_FILE" 2>&1
    elif command -v rar &>/dev/null; then
        rar x -o+ vim.rar >> "$LOG_FILE" 2>&1
    else
        log_err "rar/unrar 不可用，无法解压 vim 模版"
        mark_result 3 "FAIL"
        rm -rf "$TMP_VIM"
        # 跳到下一步（使用函数避免嵌套问题）
    fi

    # 查找解压出的 .vimrc 和 .vim 目录，部署到 /root
    if [[ "${RESULTS[3]:-}" != "FAIL" ]]; then
        # 解压后通常在当前目录产生 .vimrc 和 .vim/
        if [[ -f "$TMP_VIM/.vimrc" ]]; then
            cp -f "$TMP_VIM/.vimrc" /root/.vimrc
            log_ok "已部署 /root/.vimrc"
        fi
        if [[ -d "$TMP_VIM/.vim" ]]; then
            cp -rf "$TMP_VIM/.vim" /root/.vim
            log_ok "已部署 /root/.vim/"
        fi

        # 如果解压出的不是隐藏文件，可能在子目录中
        if [[ ! -f /root/.vimrc && ! -d /root/.vim ]]; then
            # 尝试查找
            FOUND_VIMRC=$(find "$TMP_VIM" -name ".vimrc" -o -name "vimrc" 2>/dev/null | head -1)
            FOUND_VIMDIR=$(find "$TMP_VIM" -type d \( -name ".vim" -o -name "vim" \) 2>/dev/null | head -1)
            if [[ -n "$FOUND_VIMRC" ]]; then
                cp -f "$FOUND_VIMRC" /root/.vimrc
                log_ok "已部署 /root/.vimrc (从 $FOUND_VIMRC)"
            fi
            if [[ -n "$FOUND_VIMDIR" ]]; then
                cp -rf "$FOUND_VIMDIR" /root/.vim
                log_ok "已部署 /root/.vim/ (从 $FOUND_VIMDIR)"
            fi
        fi

        if [[ -f /root/.vimrc ]] || [[ -d /root/.vim ]]; then
            mark_result 3 "OK"
        else
            log_warn "VIM 模版解压后未找到 .vimrc/.vim，请手动确认 rar 包内容"
            mark_result 3 "FAIL"
        fi
    fi

    cd /
    rm -rf "$TMP_VIM"
else
    log_err "vim.rar 下载失败"
    rm -rf "$TMP_VIM"
    mark_result 3 "FAIL"
fi

# =============================================================================
#  [5/14] 时区设置 - 北京时间
# =============================================================================
log_step "设置时区为 Asia/Shanghai (北京时间)"

CURRENT_TZ=$(timedatectl show --property=Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo "unknown")
if [[ "$CURRENT_TZ" == "Asia/Shanghai" ]]; then
    log_warn "时区已是 Asia/Shanghai，跳过"
    mark_result 4 "SKIP"
else
    log_info "当前时区: $CURRENT_TZ → 切换到 Asia/Shanghai"
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    echo "Asia/Shanghai" > /etc/timezone
    # 如果 timedatectl 可用则同步设置
    if command -v timedatectl &>/dev/null; then
        timedatectl set-timezone Asia/Shanghai >> "$LOG_FILE" 2>&1 || true
    fi
    # 同步硬件时钟
    if command -v hwclock &>/dev/null; then
        hwclock --systohc >> "$LOG_FILE" 2>&1 || true
    fi

    NEW_TZ=$(timedatectl show --property=Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo "unknown")
    if [[ "$NEW_TZ" == "Asia/Shanghai" ]]; then
        log_ok "时区已设置为 Asia/Shanghai，当前时间: $(date '+%Y-%m-%d %H:%M:%S %Z')"
        mark_result 4 "OK"
    else
        log_err "时区设置失败，当前: $NEW_TZ"
        mark_result 4 "FAIL"
    fi
fi

# =============================================================================
#  [6/14] inotify 内核限制解除
# =============================================================================
log_step "解除 inotify 内核限制 (max_user_watches & max_user_instances)"

SYSCTL_CONF="/etc/sysctl.conf"
SYSCTL_CHANGED=0

# max_user_watches
if grep -qE "^fs\.inotify\.max_user_watches\s*=" "$SYSCTL_CONF" 2>/dev/null; then
    CURRENT_VAL=$(grep -oP '^fs\.inotify\.max_user_watches\s*=\s*\K\d+' "$SYSCTL_CONF" || echo "0")
    if [[ "$CURRENT_VAL" -ge 524288 ]]; then
        log_info "  ✓ max_user_watches 已设置为 $CURRENT_VAL，跳过"
    else
        log_info "  → max_user_watches 当前值 $CURRENT_VAL，更新为 524288"
        sed -i "s/^fs\.inotify\.max_user_watches\s*=.*/fs.inotify.max_user_watches=524288/" "$SYSCTL_CONF"
        SYSCTL_CHANGED=1
    fi
else
    echo "fs.inotify.max_user_watches=524288" >> "$SYSCTL_CONF"
    log_ok "  ✓ max_user_watches=524288 已写入"
    SYSCTL_CHANGED=1
fi

# max_user_instances
if grep -qE "^fs\.inotify\.max_user_instances\s*=" "$SYSCTL_CONF" 2>/dev/null; then
    CURRENT_VAL=$(grep -oP '^fs\.inotify\.max_user_instances\s*=\s*\K\d+' "$SYSCTL_CONF" || echo "0")
    if [[ "$CURRENT_VAL" -ge 524288 ]]; then
        log_info "  ✓ max_user_instances 已设置为 $CURRENT_VAL，跳过"
    else
        log_info "  → max_user_instances 当前值 $CURRENT_VAL，更新为 524288"
        sed -i "s/^fs\.inotify\.max_user_instances\s*=.*/fs.inotify.max_user_instances=524288/" "$SYSCTL_CONF"
        SYSCTL_CHANGED=1
    fi
else
    echo "fs.inotify.max_user_instances=524288" >> "$SYSCTL_CONF"
    log_ok "  ✓ max_user_instances=524288 已写入"
    SYSCTL_CHANGED=1
fi

# 生效
if [[ $SYSCTL_CHANGED -eq 1 ]]; then
    sysctl -p >> "$LOG_FILE" 2>&1
fi

# 验证内核当前值
LIVE_WATCHES=$(cat /proc/sys/fs/inotify/max_user_watches 2>/dev/null || echo "N/A")
LIVE_INSTANCES=$(cat /proc/sys/fs/inotify/max_user_instances 2>/dev/null || echo "N/A")
log_ok "当前生效值: max_user_watches=$LIVE_WATCHES, max_user_instances=$LIVE_INSTANCES"
mark_result 5 "OK"

# =============================================================================
#  [7/14] wondershaper 限速工具
# =============================================================================
log_step "安装 wondershaper 限速工具 (全局命令)"

if command -v wondershaper &>/dev/null; then
    log_warn "wondershaper 已安装，跳过"
    mark_result 6 "SKIP"
else
    WONDER_DIR="/opt/wondershaper"

    # 清理旧安装
    rm -rf "$WONDER_DIR"

    log_info "克隆 wondershaper 仓库..."
    if git clone --depth=1 https://github.com/magnific0/wondershaper.git "$WONDER_DIR" >> "$LOG_FILE" 2>&1; then
        # 安装方式1: 使用 Makefile（如果存在）
        if [[ -f "$WONDER_DIR/Makefile" ]]; then
            cd "$WONDER_DIR"
            make install >> "$LOG_FILE" 2>&1 || true
            cd /
        fi

        # 安装方式2: 确保 /usr/local/sbin 下有符号链接（兜底）
        if [[ ! -f /usr/local/sbin/wondershaper && ! -f /usr/sbin/wondershaper && ! -f /usr/local/bin/wondershaper ]]; then
            if [[ -f "$WONDER_DIR/wondershaper" ]]; then
                chmod +x "$WONDER_DIR/wondershaper"
                ln -sf "$WONDER_DIR/wondershaper" /usr/local/sbin/wondershaper
                log_info "已创建符号链接 /usr/local/sbin/wondershaper"
            fi
        fi

        # 验证
        if command -v wondershaper &>/dev/null; then
            log_ok "wondershaper 安装成功，可直接运行: wondershaper -a <interface> -d <down_kbps> -u <up_kbps>"
            log_info "示例: wondershaper -a enp4s0 -d 8192 -u 8192"
            mark_result 6 "OK"
        else
            # 再尝试直接加到 PATH 路径
            if [[ -f "$WONDER_DIR/wondershaper" ]]; then
                ln -sf "$WONDER_DIR/wondershaper" /usr/local/bin/wondershaper
                chmod +x /usr/local/bin/wondershaper
                log_ok "wondershaper 已链接到 /usr/local/bin/wondershaper"
                mark_result 6 "OK"
            else
                log_err "wondershaper 安装后命令不可用"
                mark_result 6 "FAIL"
            fi
        fi
    else
        log_err "wondershaper 仓库克隆失败"
        mark_result 6 "FAIL"
    fi
fi

# =============================================================================
#  [8/14] rclone 稳定版
# =============================================================================
log_step "安装 rclone 稳定版"

if command -v rclone &>/dev/null; then
    RCLONE_VER=$(rclone version --check 2>/dev/null | head -1 || rclone --version 2>/dev/null | head -1 || echo "已安装")
    log_warn "rclone 已安装: $RCLONE_VER，跳过 (如需升级请运行: rclone selfupdate)"
    mark_result 7 "SKIP"
else
    log_info "使用官方安装脚本安装 rclone..."
    if curl -fsSL https://rclone.org/install.sh | bash >> "$LOG_FILE" 2>&1; then
        if command -v rclone &>/dev/null; then
            log_ok "rclone 安装成功: $(rclone --version 2>/dev/null | head -1)"
            mark_result 7 "OK"
        else
            log_err "rclone 安装脚本执行成功但命令不可用"
            mark_result 7 "FAIL"
        fi
    else
        log_err "rclone 官方安装脚本执行失败"
        mark_result 7 "FAIL"
    fi
fi

# =============================================================================
#  [9/14] qBittorrent-nox 4.3.9
# =============================================================================
log_step "安装 qBittorrent-nox 4.3.9"

# 检查是否已安装目标版本
if command -v qbittorrent-nox &>/dev/null; then
    QB_INSTALLED_VER=$(qbittorrent-nox --version 2>/dev/null || echo "unknown")
    if echo "$QB_INSTALLED_VER" | grep -q "4\.3\.9"; then
        log_warn "qBittorrent-nox 4.3.9 已安装，跳过"
        mark_result 8 "SKIP"
    else
        log_info "已安装版本: $QB_INSTALLED_VER，将替换为 4.3.9"
    fi
fi

if [[ "${RESULTS[8]:-}" != "SKIP" ]]; then
    # 方案: 使用 userdocs/qbittorrent-nox-static 项目的静态编译版本
    # 该项目提供多版本静态编译的 qbittorrent-nox，无外部依赖
    QB_STATIC_BASE="https://github.com/userdocs/qbittorrent-nox-static/releases/download"

    # qBittorrent 4.3.9 对应 libtorrent v1.2.19 或 v2.0.x
    # 尝试多个已知可用的 release tag
    QB_DOWNLOADED=0

    if [[ "$ARCH" == "x86_64" ]]; then
        QB_ARCH="x86_64"
    elif [[ "$ARCH" == "aarch64" ]]; then
        QB_ARCH="aarch64"
    fi

    # 依次尝试可能的 release tag 格式
    QB_TAGS=(
        "release-4.3.9_v2.0.8"
        "release-4.3.9_v1.2.19"
        "release-4.3.9_v2.0.9"
        "release-4.3.9_v1.2.18"
    )

    for tag in "${QB_TAGS[@]}"; do
        QB_URL="${QB_STATIC_BASE}/${tag}/${QB_ARCH}-qbittorrent-nox"
        log_info "尝试下载: $QB_URL"
        if wget -q --timeout=30 -O /tmp/qbittorrent-nox "$QB_URL" 2>> "$LOG_FILE"; then
            # 验证是否为有效的 ELF 二进制
            if file /tmp/qbittorrent-nox | grep -q "ELF"; then
                QB_DOWNLOADED=1
                log_ok "下载成功 (tag: $tag)"
                break
            else
                log_warn "下载的文件不是有效的 ELF 二进制，尝试下一个 tag"
                rm -f /tmp/qbittorrent-nox
            fi
        else
            log_warn "tag $tag 下载失败，尝试下一个..."
        fi
    done

    # 如果静态版本都失败，尝试 GitHub Releases API 自动搜索
    if [[ $QB_DOWNLOADED -eq 0 ]]; then
        log_info "尝试通过 GitHub API 查找 4.3.9 静态版本..."
        QB_API_URL="https://api.github.com/repos/userdocs/qbittorrent-nox-static/releases"
        QB_RELEASE_URL=$(curl -fsSL "$QB_API_URL" 2>/dev/null \
            | grep -oP '"browser_download_url":\s*"\K[^"]*4\.3\.9[^"]*'"${QB_ARCH}"'[^"]*' \
            | head -1 || true)

        if [[ -n "$QB_RELEASE_URL" ]]; then
            log_info "找到: $QB_RELEASE_URL"
            if wget -q --timeout=60 -O /tmp/qbittorrent-nox "$QB_RELEASE_URL" 2>> "$LOG_FILE"; then
                if file /tmp/qbittorrent-nox | grep -q "ELF"; then
                    QB_DOWNLOADED=1
                    log_ok "下载成功 (via API)"
                fi
            fi
        fi
    fi

    if [[ $QB_DOWNLOADED -eq 1 ]]; then
        # 停止正在运行的旧版本（如有）
        systemctl stop qbittorrent-nox 2>/dev/null || true

        chmod 755 /tmp/qbittorrent-nox
        mv -f /tmp/qbittorrent-nox /usr/local/bin/qbittorrent-nox

        # 验证
        QB_VER=$(qbittorrent-nox --version 2>/dev/null || echo "installed")
        log_ok "qBittorrent-nox 安装成功: $QB_VER"

        # 创建 systemd 服务文件（如不存在）
        QB_SERVICE="/etc/systemd/system/qbittorrent-nox.service"
        if [[ ! -f "$QB_SERVICE" ]]; then
            log_info "创建 systemd 服务文件..."
            cat > "$QB_SERVICE" << 'QBEOF'
[Unit]
Description=qBittorrent-nox Daemon
Documentation=man:qbittorrent-nox(1)
Wants=network-online.target
After=network-online.target nss-lookup.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/qbittorrent-nox --webui-port=8080
Restart=on-failure
RestartSec=5
TimeoutStopSec=300

[Install]
WantedBy=multi-user.target
QBEOF
            systemctl daemon-reload >> "$LOG_FILE" 2>&1
            log_ok "systemd 服务已创建 (端口 8080)，启用: systemctl enable --now qbittorrent-nox"
        fi

        mark_result 8 "OK"
    else
        log_err "qBittorrent-nox 4.3.9 所有下载源均失败"
        log_info "手动安装方式: https://github.com/userdocs/qbittorrent-nox-static"
        mark_result 8 "FAIL"
    fi
fi

# =============================================================================
#  [10/14] Python 3.12 + pip3
# =============================================================================
log_step "安装 Python 3.12 + pip3"

# 检查是否已有 Python 3.12+
PY312_CMD=""
for cmd in python3.12 python3.13 python3.14; do
    if command -v "$cmd" &>/dev/null; then
        PY312_CMD="$cmd"
        break
    fi
done

if [[ -n "$PY312_CMD" ]]; then
    PY_VER=$($PY312_CMD --version 2>/dev/null)
    log_warn "已检测到 $PY_VER ($PY312_CMD)，跳过编译安装"
    # 确保 pip 可用
    if ! $PY312_CMD -m pip --version &>/dev/null; then
        log_info "为 $PY312_CMD 安装 pip..."
        $PY312_CMD -m ensurepip --upgrade >> "$LOG_FILE" 2>&1 || true
    fi
    mark_result 9 "SKIP"
else
    # 从源码编译安装 Python 3.12
    PY_VERSION="3.12.8"
    PY_URL="https://www.python.org/ftp/python/${PY_VERSION}/Python-${PY_VERSION}.tar.xz"

    log_info "安装编译依赖..."
    apt-get install -y -qq \
        build-essential zlib1g-dev libncurses5-dev libgdbm-dev \
        libnss3-dev libssl-dev libreadline-dev libffi-dev \
        libsqlite3-dev libbz2-dev liblzma-dev \
        >> "$LOG_FILE" 2>&1

    TMP_PY=$(mktemp -d)
    log_info "下载 Python $PY_VERSION 源码..."

    if wget -q --show-progress -O "$TMP_PY/Python.tar.xz" "$PY_URL" 2>> "$LOG_FILE"; then
        cd "$TMP_PY"
        tar -xf Python.tar.xz >> "$LOG_FILE" 2>&1
        cd "Python-${PY_VERSION}"

        log_info "配置编译参数 (--enable-optimizations)... 这可能需要几分钟"
        ./configure --enable-optimizations --prefix=/usr/local >> "$LOG_FILE" 2>&1

        # 获取 CPU 核心数用于并行编译
        NPROC=$(nproc 2>/dev/null || echo 2)
        log_info "开始编译 (并行线程: $NPROC)... 这可能需要 5~15 分钟"
        make -j"$NPROC" >> "$LOG_FILE" 2>&1

        log_info "安装 Python $PY_VERSION (altinstall 模式，不覆盖系统 Python)..."
        make altinstall >> "$LOG_FILE" 2>&1

        cd /
        rm -rf "$TMP_PY"

        # 验证
        if command -v python3.12 &>/dev/null; then
            log_ok "Python 安装成功: $(python3.12 --version)"

            # 确保 pip 可用
            python3.12 -m ensurepip --upgrade >> "$LOG_FILE" 2>&1 || true
            python3.12 -m pip install --upgrade pip >> "$LOG_FILE" 2>&1 || true

            PIP_VER=$(python3.12 -m pip --version 2>/dev/null || echo "N/A")
            log_ok "pip3 版本: $PIP_VER"

            mark_result 9 "OK"
        else
            log_err "Python 编译安装后命令不可用"
            mark_result 9 "FAIL"
        fi
    else
        log_err "Python 源码下载失败"
        rm -rf "$TMP_PY"
        mark_result 9 "FAIL"
    fi
fi

# =============================================================================
#  [11/14] 系统监控工具集
# =============================================================================
log_step "安装系统监控工具集 (nload iftop htop ncdu iotop)"

# nload   — 实时网卡上传/下载速度可视化 (条形图)
# iftop   — 按连接维度显示实时带宽占用
# htop    — 交互式进程/CPU/内存监控
# ncdu    — 交互式磁盘空间分析 (比 du 直观得多)
# iotop   — 实时查看磁盘 IO 占用进程
MON_PKGS="nload iftop htop ncdu iotop"
MON_FAIL=0

for pkg in $MON_PKGS; do
    if dpkg -s "$pkg" &>/dev/null; then
        log_info "  ✓ $pkg 已安装，跳过"
    else
        log_info "  → 正在安装 $pkg ..."
        if apt-get install -y -qq "$pkg" >> "$LOG_FILE" 2>&1; then
            log_ok "  ✓ $pkg 安装成功"
        else
            log_err "  ✗ $pkg 安装失败"
            MON_FAIL=1
        fi
    fi
done

if [[ $MON_FAIL -eq 0 ]]; then
    mark_result 10 "OK"
    log_info "常用命令速查:"
    log_info "  nload           — 实时查看网卡上传/下载速度"
    log_info "  iftop -i eth0   — 按连接显示带宽占用"
    log_info "  htop            — 交互式 CPU/内存/进程监控"
    log_info "  ncdu /          — 交互式磁盘空间分析"
    log_info "  iotop           — 实时磁盘 IO 监控"
    log_info "  df -hT          — 查看磁盘空间总览"
    log_info "  free -h         — 查看内存使用"
    log_info "  uptime          — 查看运行时间与负载"
else
    mark_result 10 "FAIL"
fi

# =============================================================================
#  [12/14] 硬盘 IO 基准测试 (fio)
# =============================================================================
log_step "安装硬盘 IO 基准测试工具 (fio)"

if command -v fio &>/dev/null; then
    FIO_VER=$(fio --version 2>/dev/null || echo "已安装")
    log_warn "fio 已安装: $FIO_VER，跳过"
    mark_result 11 "SKIP"
else
    log_info "正在安装 fio ..."
    if apt-get install -y -qq fio >> "$LOG_FILE" 2>&1; then
        log_ok "fio 安装成功: $(fio --version 2>/dev/null)"
        log_info "常用基准测试命令:"
        log_info "  顺序读:   fio --name=seqread  --rw=read     --bs=1M --size=1G --numjobs=1 --runtime=30 --group_reporting"
        log_info "  顺序写:   fio --name=seqwrite --rw=write    --bs=1M --size=1G --numjobs=1 --runtime=30 --group_reporting"
        log_info "  随机读写: fio --name=randrw    --rw=randrw  --bs=4K --size=1G --numjobs=4 --runtime=30 --group_reporting"
        mark_result 11 "OK"
    else
        log_err "fio 安装失败"
        mark_result 11 "FAIL"
    fi
fi

# =============================================================================
#  [13/14] FileBrowser — 现代化 HTTP 文件下载服务 (带认证)
# =============================================================================
log_step "安装 FileBrowser HTTP 文件下载服务 (带账号密码认证)"

# FileBrowser: https://filebrowser.org/
# 特性: 现代化 Web UI、文件上传下载、内置用户认证、多用户支持、拖拽操作
# 默认监听 :8081，WebUI 访问后首次登录 admin/admin (脚本会提示修改)

FB_PORT=8081
FB_ROOT="/srv/filebrowser"      # 默认共享目录
FB_DB="/etc/filebrowser/filebrowser.db"
FB_CONFIG="/etc/filebrowser/.filebrowser.json"

if command -v filebrowser &>/dev/null; then
    FB_VER=$(filebrowser version 2>/dev/null || echo "已安装")
    log_warn "FileBrowser 已安装: $FB_VER，跳过"
    mark_result 12 "SKIP"
else
    log_info "使用官方安装脚本安装 FileBrowser..."
    if curl -fsSL https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash >> "$LOG_FILE" 2>&1; then
        if command -v filebrowser &>/dev/null; then
            FB_VER=$(filebrowser version 2>/dev/null || echo "installed")
            log_ok "FileBrowser 安装成功: $FB_VER"

            # 创建配置目录和共享目录
            mkdir -p "$(dirname "$FB_DB")" "$FB_ROOT"

            # 初始化配置（如不存在）
            if [[ ! -f "$FB_CONFIG" ]]; then
                cat > "$FB_CONFIG" << FBEOF
{
  "port": ${FB_PORT},
  "baseURL": "",
  "address": "0.0.0.0",
  "log": "/var/log/filebrowser.log",
  "database": "${FB_DB}",
  "root": "${FB_ROOT}"
}
FBEOF
                log_ok "配置文件已创建: $FB_CONFIG"
            fi

            # 初始化数据库（设置默认 admin 用户）
            if [[ ! -f "$FB_DB" ]]; then
                filebrowser config init --config "$FB_CONFIG" >> "$LOG_FILE" 2>&1 || true
                filebrowser users add admin admin --perm.admin --config "$FB_CONFIG" >> "$LOG_FILE" 2>&1 || true
                log_ok "默认管理员账号: admin / admin (请首次登录后立即修改密码！)"
            fi

            # 创建 systemd 服务
            FB_SERVICE="/etc/systemd/system/filebrowser.service"
            if [[ ! -f "$FB_SERVICE" ]]; then
                cat > "$FB_SERVICE" << 'FBSEOF'
[Unit]
Description=FileBrowser - Web File Manager
Documentation=https://filebrowser.org/
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/filebrowser --config /etc/filebrowser/.filebrowser.json
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
FBSEOF
                systemctl daemon-reload >> "$LOG_FILE" 2>&1
                log_ok "systemd 服务已创建"
            fi

            log_info "┌─────────────────────────────────────────────────┐"
            log_info "│  FileBrowser 配置摘要                           │"
            log_info "├─────────────────────────────────────────────────┤"
            log_info "│  Web 地址:   http://<服务器IP>:${FB_PORT}        │"
            log_info "│  共享目录:   ${FB_ROOT}                         │"
            log_info "│  默认账号:   admin / admin                      │"
            log_info "│  启动命令:   systemctl enable --now filebrowser │"
            log_info "│  ⚠️  请首次登录后立即修改默认密码！             │"
            log_info "└─────────────────────────────────────────────────┘"

            mark_result 12 "OK"
        else
            log_err "FileBrowser 安装脚本执行成功但命令不可用"
            mark_result 12 "FAIL"
        fi
    else
        log_err "FileBrowser 安装脚本执行失败"
        mark_result 12 "FAIL"
    fi
fi

# =============================================================================
#  [14/14] Docker + Docker Compose 稳定版
# =============================================================================
log_step "安装 Docker CE + Docker Compose 稳定版"

if command -v docker &>/dev/null; then
    DOCKER_VER=$(docker --version 2>/dev/null || echo "已安装")
    log_warn "Docker 已安装: $DOCKER_VER"

    # 检查 Docker Compose (v2 plugin 方式)
    if docker compose version &>/dev/null; then
        COMPOSE_VER=$(docker compose version 2>/dev/null)
        log_warn "Docker Compose 已安装: $COMPOSE_VER，跳过"
        mark_result 13 "SKIP"
    else
        log_info "Docker 已安装但缺少 Compose 插件，将单独安装..."
        apt-get install -y -qq docker-compose-plugin >> "$LOG_FILE" 2>&1 || true
        if docker compose version &>/dev/null; then
            log_ok "Docker Compose 插件安装成功: $(docker compose version)"
            mark_result 13 "OK"
        else
            log_err "Docker Compose 插件安装失败"
            mark_result 13 "FAIL"
        fi
    fi
else
    # ======================== 方案1: 官方 apt 仓库 (推荐) ========================
    log_info "配置 Docker 官方 apt 仓库..."

    # 安装依赖
    apt-get install -y -qq ca-certificates curl gnupg >> "$LOG_FILE" 2>&1

    # 添加 Docker 官方 GPG 密钥
    install -m 0755 -d /etc/apt/keyrings
    if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
        curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg >> "$LOG_FILE" 2>&1
        chmod a+r /etc/apt/keyrings/docker.gpg
        log_ok "Docker GPG 密钥已导入"
    fi

    # 添加 Docker apt 源
    DOCKER_LIST="/etc/apt/sources.list.d/docker.list"
    if [[ ! -f "$DOCKER_LIST" ]]; then
        echo \
            "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
            $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > "$DOCKER_LIST"
        log_ok "Docker apt 源已添加"
    fi

    # 更新索引并安装
    apt-get update -qq >> "$LOG_FILE" 2>&1

    log_info "正在安装 docker-ce docker-ce-cli containerd.io docker-compose-plugin ..."
    DOCKER_INSTALL_OK=1
    if apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >> "$LOG_FILE" 2>&1; then
        log_ok "Docker CE 安装成功"
    else
        log_warn "apt 仓库安装失败，尝试使用官方便捷脚本 (get.docker.com)..."
        DOCKER_INSTALL_OK=0
    fi

    # ======================== 方案2: 便捷脚本兜底 ========================
    if [[ $DOCKER_INSTALL_OK -eq 0 ]]; then
        if curl -fsSL https://get.docker.com | bash >> "$LOG_FILE" 2>&1; then
            log_ok "Docker CE 通过便捷脚本安装成功"
            # 便捷脚本可能不包含 compose 插件，单独安装
            apt-get install -y -qq docker-compose-plugin >> "$LOG_FILE" 2>&1 || true
        else
            log_err "Docker 所有安装方式均失败"
            mark_result 13 "FAIL"
        fi
    fi

    # 最终验证
    if [[ "${RESULTS[13]:-}" != "FAIL" ]]; then
        if command -v docker &>/dev/null; then
            # 启用并启动 Docker 服务
            systemctl enable docker >> "$LOG_FILE" 2>&1 || true
            systemctl start docker >> "$LOG_FILE" 2>&1 || true

            DOCKER_VER=$(docker --version 2>/dev/null)
            log_ok "Docker 版本: $DOCKER_VER"

            if docker compose version &>/dev/null; then
                COMPOSE_VER=$(docker compose version 2>/dev/null)
                log_ok "Docker Compose 版本: $COMPOSE_VER"
            else
                log_warn "Docker Compose 插件未安装，可手动安装: apt install docker-compose-plugin"
            fi

            # 验证 Docker 引擎是否可运行
            if docker info &>/dev/null; then
                log_ok "Docker 引擎运行正常"
            else
                log_warn "Docker 引擎已安装但 daemon 未正常启动，请检查: systemctl status docker"
            fi

            mark_result 13 "OK"
        else
            log_err "Docker 安装后命令不可用"
            mark_result 13 "FAIL"
        fi
    fi
fi

# =============================================================================
#  汇总报告
# =============================================================================

echo "" | tee -a "$LOG_FILE"
echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}" | tee -a "$LOG_FILE"
echo -e "${BOLD}║               📊  安装结果汇总报告                         ║${NC}" | tee -a "$LOG_FILE"
echo -e "${BOLD}╠══════════════════════════════════════════════════════════════╣${NC}" | tee -a "$LOG_FILE"

OK_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

for i in $(seq 0 $((TOTAL_STEPS - 1))); do
    STATUS="${RESULTS[$i]:-UNKNOWN}"
    STEP_NAME="${STEP_NAMES[$i]}"
    STEP_NUM=$((i + 1))

    case "$STATUS" in
        OK)
            STATUS_ICON="${GREEN}✅ 成功${NC}"
            OK_COUNT=$((OK_COUNT + 1))
            ;;
        FAIL)
            STATUS_ICON="${RED}❌ 失败${NC}"
            FAIL_COUNT=$((FAIL_COUNT + 1))
            ;;
        SKIP)
            STATUS_ICON="${YELLOW}⏭️  跳过${NC}"
            SKIP_COUNT=$((SKIP_COUNT + 1))
            ;;
        *)
            STATUS_ICON="${YELLOW}❓ 未知${NC}"
            ;;
    esac

    printf "  ${BOLD}[%2d/%-2d]${NC}  %-28s %b\n" "$STEP_NUM" "$TOTAL_STEPS" "$STEP_NAME" "$STATUS_ICON" | tee -a "$LOG_FILE"
done

echo -e "${BOLD}╠══════════════════════════════════════════════════════════════╣${NC}" | tee -a "$LOG_FILE"
echo -e "  ${GREEN}成功: $OK_COUNT${NC}    ${RED}失败: $FAIL_COUNT${NC}    ${YELLOW}跳过: $SKIP_COUNT${NC}" | tee -a "$LOG_FILE"
echo -e "${BOLD}╠══════════════════════════════════════════════════════════════╣${NC}" | tee -a "$LOG_FILE"
echo -e "  完成时间: $(date '+%Y-%m-%d %H:%M:%S %Z')" | tee -a "$LOG_FILE"
echo -e "  详细日志: ${CYAN}$LOG_FILE${NC}" | tee -a "$LOG_FILE"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}" | tee -a "$LOG_FILE"

# 如果有失败项，退出码为 1
if [[ $FAIL_COUNT -gt 0 ]]; then
    echo "" | tee -a "$LOG_FILE"
    log_warn "有 $FAIL_COUNT 个组件安装失败，请查看日志排查: cat $LOG_FILE"
    exit 1
fi

log_ok "🎉 所有组件安装完毕！Seedbox 服务器初始化成功。"
exit 0
