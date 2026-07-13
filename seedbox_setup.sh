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
#    [9]  Python 3.12 + pip3
#    [10] 系统监控工具集 (nload iftop htop ncdu iotop)
#    [11] 硬盘 IO 基准测试 (fio)
#    [12] FileBrowser HTTP 文件下载服务 (带认证)
#    [13] Docker + Docker Compose 稳定版
#===============================================================================

set -euo pipefail

# 显式将 /usr/local/sbin 和 /usr/local/bin 写入 PATH 环境变量，避免 command -v 或执行新安装命令失败
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

# ============================= 颜色与日志 =====================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

TOTAL_STEPS=13
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

# 将 /usr/local/bin 和 /usr/local/sbin 配置到全局 PATH 中，防备某些 Debian 精简版没有内置该环境
if ! grep -q "/usr/local/bin" /etc/profile 2>/dev/null; then
    echo 'export PATH="/usr/local/sbin:/usr/local/bin:$PATH"' >> /etc/profile
    log_ok "全局配置文件 /etc/profile 已追加 /usr/local/bin"
fi

if ! grep -q "/usr/local/bin" /root/.bashrc 2>/dev/null; then
    echo 'export PATH="/usr/local/sbin:/usr/local/bin:$PATH"' >> /root/.bashrc
    log_ok "用户配置文件 /root/.bashrc 已追加 /usr/local/bin"
fi

# 开启 root 终端命令提示符彩色显示及常用别名 (自动清理旧版配置并覆盖)
sed -i '/# 开启终端彩色显示/,/egrep=/d' /root/.bashrc 2>/dev/null || true
cat >> /root/.bashrc << 'EOF'

# 开启终端彩色显示
force_color_prompt=yes
if [ -n "$force_color_prompt" ]; then
    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
        color_prompt=yes
    else
        color_prompt=
    fi
fi

if [ "$color_prompt" = yes ]; then
    # 使用用户指定的彩色配色组合
    PS1='\[\e[1;31m\]\u\[\e[1;33m\]@\[\e[1;36m\]\h \[\e[1;33m\]\w \[\e[1;35m\]\$ \[\e[0m\]'
else
    PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi
unset color_prompt force_color_prompt

# 开启常用彩色别名
alias ls='ls --color=auto'
alias ll='ls -lah --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'
EOF
log_ok "root 用户的终端彩色命令提示符 (PS1) 及彩色别名已覆盖配置"

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

# ============================= 网络环境探测 ===================================
log_info "正在检测网络环境 (国内/国外 IP)..."
IS_CN=0
PROXY_PREFIX=""

# 探测当前服务器地理位置是否在中国大陆 (使用系统自带的 wget，因为此时 curl 可能未安装)
if wget -qO- --timeout=3 --no-check-certificate https://ipapi.co/country/ 2>/dev/null | grep -q "CN"; then
    IS_CN=1
elif wget -qO- --timeout=3 --no-check-certificate https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | grep -q "loc=CN"; then
    IS_CN=1
elif ! wget -q --spider --timeout=3 --no-check-certificate https://www.google.com &>/dev/null; then
    IS_CN=1
fi

if [[ $IS_CN -eq 1 ]]; then
    log_info "检测到当前服务器位于中国大陆，将自动配置国内镜像源并启用 GitHub 加速代理"
    PROXY_PREFIX="https://mirror.ghproxy.com/"
else
    log_info "检测到当前服务器位于海外，将使用官方默认源与直连下载"
fi

# ============================= apt 源更新 =====================================

if [[ $IS_CN -eq 1 ]]; then
    log_info "备份并配置 Debian ${DEBIAN_VERSION} (${VERSION_CODENAME}) 清华大学 APT 镜像源..."
    cp -n /etc/apt/sources.list /etc/apt/sources.list.bak 2>/dev/null || true

    CODENAME="$VERSION_CODENAME"
    if [[ "$DEBIAN_VERSION" -ge 12 ]]; then
        COMPONENTS="main contrib non-free non-free-firmware"
    else
        COMPONENTS="main contrib non-free"
    fi

    cat > /etc/apt/sources.list << EOF
deb http://mirrors.tuna.tsinghua.edu.cn/debian/ ${CODENAME} ${COMPONENTS}
deb-src http://mirrors.tuna.tsinghua.edu.cn/debian/ ${CODENAME} ${COMPONENTS}

deb http://mirrors.tuna.tsinghua.edu.cn/debian/ ${CODENAME}-updates ${COMPONENTS}
deb-src http://mirrors.tuna.tsinghua.edu.cn/debian/ ${CODENAME}-updates ${COMPONENTS}

deb http://mirrors.tuna.tsinghua.edu.cn/debian/ ${CODENAME}-backports ${COMPONENTS}
deb-src http://mirrors.tuna.tsinghua.edu.cn/debian/ ${CODENAME}-backports ${COMPONENTS}

deb http://mirrors.tuna.tsinghua.edu.cn/debian-security ${CODENAME}-security ${COMPONENTS}
deb-src http://mirrors.tuna.tsinghua.edu.cn/debian-security ${CODENAME}-security ${COMPONENTS}
EOF
    log_ok "APT 软件源已成功更换为清华大学镜像源"
else
    log_info "跳过更换国内软件源 (当前使用系统默认源)"
fi

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
            log_warn "  → 首次安装 $pkg 失败，尝试修复依赖并重试..."
            apt-get install -f -y >> "$LOG_FILE" 2>&1 || true
            apt-get update -qq >> "$LOG_FILE" 2>&1 || true
            if apt-get install -y -qq "$pkg" >> "$LOG_FILE" 2>&1; then
                log_ok "  ✓ $pkg 修复依赖后安装成功"
            else
                log_err "  ✗ $pkg 安装失败"
                if [[ -f "$LOG_FILE" ]]; then
                    log_err "    错误详情 (最近15行日志):"
                    tail -n 15 "$LOG_FILE" | sed 's/^/    /g'
                fi
                INSTALL_FAIL=1
            fi
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
    if wget -q --show-progress --no-check-certificate -O "$TMP_RAR/rar.tar.gz" "$RAR_URL" 2>> "$LOG_FILE"; then
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
            if [[ -f /usr/local/bin/rar ]]; then
                log_err "    检测到 /usr/local/bin/rar 文件存在，但无法直接在 PATH 中找到。尝试直接执行结果:"
                if /usr/local/bin/rar 2>&1 | head -n 5 | sed 's/^/    /g'; then
                    log_warn "    这表明 /usr/local/bin 未能加入系统的 PATH 环境变量。虽然脚本开头已尝试修复，但若在某些特殊 Shell/Sudo 运行环境下仍然失效，建议手动将其添加到全局 PATH 中。"
                fi
            else
                log_err "    /usr/local/bin/rar 文件不存在，解压或安装可能失败。"
            fi
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
# 优先使用探测环境链接下载，失败时强制使用代理镜像重试
if wget -q --show-progress --no-check-certificate -O "$TMP_VIM/vim.rar" "${PROXY_PREFIX}${VIM_RAR_URL}" 2>> "$LOG_FILE" || \
   (log_warn "首选链接下载 vim.rar 失败，尝试通过代理镜像下载..." && \
    wget -q --show-progress --no-check-certificate -O "$TMP_VIM/vim.rar" "https://mirror.ghproxy.com/${VIM_RAR_URL}" 2>> "$LOG_FILE"); then
    cd "$TMP_VIM"
    # 确保 rar/unrar 可用 (优先使用 PATH 中的命令，其次使用绝对路径兜底)
    EXE_UNRAR="unrar"
    EXE_RAR="rar"
    if ! command -v unrar &>/dev/null && [[ -x /usr/local/bin/unrar ]]; then
        EXE_UNRAR="/usr/local/bin/unrar"
    fi
    if ! command -v rar &>/dev/null && [[ -x /usr/local/bin/rar ]]; then
        EXE_RAR="/usr/local/bin/rar"
    fi

    if command -v "$EXE_UNRAR" &>/dev/null || [[ "$EXE_UNRAR" == /* ]]; then
        "$EXE_UNRAR" x -o+ vim.rar >> "$LOG_FILE" 2>&1
    elif command -v "$EXE_RAR" &>/dev/null || [[ "$EXE_RAR" == /* ]]; then
        "$EXE_RAR" x -o+ vim.rar >> "$LOG_FILE" 2>&1
    else
        log_err "rar/unrar 不可用，无法解压 vim 模版"
        mark_result 3 "FAIL"
        rm -rf "$TMP_VIM"
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
#  [6/13] inotify 内核限制解除
# =============================================================================
log_step "解除 inotify 内核限制 (max_user_watches & max_user_instances)"

SYSCTL_CONF="/etc/sysctl.conf"
SYSCTL_CHANGED=0

# max_user_watches
if grep -qE "^fs\.inotify\.max_user_watches\s*=" "$SYSCTL_CONF" 2>/dev/null; then
    CURRENT_VAL=$(grep -oP '^fs\.inotify\.max_user_watches\s*=\s*\K\d+' "$SYSCTL_CONF" || echo "0")
    if [[ "$CURRENT_VAL" -ge 4194304 ]]; then
        log_info "  ✓ max_user_watches 已设置为 $CURRENT_VAL，跳过"
    else
        log_info "  → max_user_watches 当前值 $CURRENT_VAL，更新为 4194304"
        sed -i "s/^fs\.inotify\.max_user_watches\s*=.*/fs.inotify.max_user_watches=4194304/" "$SYSCTL_CONF"
        SYSCTL_CHANGED=1
    fi
else
    echo "fs.inotify.max_user_watches=4194304" >> "$SYSCTL_CONF"
    log_ok "  ✓ max_user_watches=4194304 已写入"
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
    sysctl -p >> "$LOG_FILE" 2>&1 || log_warn "  ⚠️ 运行 sysctl -p 失败，部分容器 (LXC/OpenVZ) 或系统内核不支持动态载入内核参数"
fi

# 验证内核当前值
LIVE_WATCHES=$(cat /proc/sys/fs/inotify/max_user_watches 2>/dev/null || echo "N/A")
LIVE_INSTANCES=$(cat /proc/sys/fs/inotify/max_user_instances 2>/dev/null || echo "N/A")
log_ok "当前生效值: max_user_watches=$LIVE_WATCHES, max_user_instances=$LIVE_INSTANCES"
if [[ "$LIVE_WATCHES" != "4194304" ]] || [[ "$LIVE_INSTANCES" != "524288" ]]; then
    log_warn "  提示: 实测生效值与期望值不完全吻合。这可能是由于当前使用的是 LXC/OpenVZ 虚拟化容器，无法修改宿主机共享的内核参数。此情况属于正常限制，不影响基础软件运行。"
fi
mark_result 5 "OK"

# =============================================================================
#  [7/13] wondershaper 限速工具
# =============================================================================
log_step "安装 wondershaper 限速工具 (全局命令)"

if command -v wondershaper &>/dev/null; then
    log_warn "wondershaper 已安装，跳过"
    mark_result 6 "SKIP"
    WONDER_DIR="/opt/wondershaper"

    # 清理旧安装
    rm -rf "$WONDER_DIR"

    log_info "克隆 wondershaper 仓库..."
    if git clone --depth=1 "${PROXY_PREFIX}https://github.com/magnific0/wondershaper.git" "$WONDER_DIR" >> "$LOG_FILE" 2>&1 || \
       (log_warn "首选链接克隆 wondershaper 仓库失败，尝试使用代理克隆..." && \
        git clone --depth=1 "https://mirror.ghproxy.com/https://github.com/magnific0/wondershaper.git" "$WONDER_DIR" >> "$LOG_FILE" 2>&1); then
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
#  [8/13] rclone 稳定版
# =============================================================================
log_step "安装 rclone 稳定版"

if command -v rclone &>/dev/null; then
    RCLONE_VER=$(rclone version --check 2>/dev/null | head -1 || rclone --version 2>/dev/null | head -1 || echo "已安装")
    log_warn "rclone 已安装: $RCLONE_VER，跳过 (如需升级请运行: rclone selfupdate)"
    mark_result 7 "SKIP"
else
    log_info "使用官方安装脚本安装 rclone..."
    if curl -fsSL -k https://rclone.org/install.sh | bash >> "$LOG_FILE" 2>&1; then
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
#  [9/13] Python 3.12 + pip3
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
    mark_result 8 "SKIP"
else
    # 优先使用 python-build-standalone 提供的预编译独立版 Python 3.12，避免耗时的编译过程
    PY_BIN_VERSION="3.12.7"
    BUILD_DATE="20241016"
    
    if [[ "$ARCH" == "x86_64" ]]; then
        PY_ARCH="x86_64-unknown-linux-gnu"
    elif [[ "$ARCH" == "aarch64" ]]; then
        PY_ARCH="aarch64-unknown-linux-gnu"
    else
        PY_ARCH=""
    fi

    PY_INSTALLED=0

    if [[ -n "$PY_ARCH" ]]; then
        PY_URL="https://github.com/astral-sh/python-build-standalone/releases/download/${BUILD_DATE}/cpython-${PY_BIN_VERSION}+${BUILD_DATE}-${PY_ARCH}-install_only.tar.gz"
        log_info "检测到系统架构: $ARCH，正在通过预编译二进制安装 Python ${PY_BIN_VERSION} (免编译极速版)..."
        
        TMP_PY=$(mktemp -d)
        
        # 尝试直接下载，失败则使用代理加速下载
        if wget -q --show-progress --no-check-certificate -O "$TMP_PY/python-bin.tar.gz" "${PROXY_PREFIX:-}${PY_URL}" 2>> "$LOG_FILE" || \
           wget -q --show-progress --no-check-certificate -O "$TMP_PY/python-bin.tar.gz" "https://mirror.ghproxy.com/${PY_URL}" 2>> "$LOG_FILE"; then
            
            log_info "下载成功，正在解压部署..."
            tar -xf "$TMP_PY/python-bin.tar.gz" -C "$TMP_PY" >> "$LOG_FILE" 2>&1
            
            if [[ -d "$TMP_PY/python/install" ]]; then
                # 清理可能存在的旧目录
                rm -rf /usr/local/python3.12
                mkdir -p /usr/local/python3.12
                # 移动到 /usr/local/python3.12
                cp -rf "$TMP_PY/python/install"/* /usr/local/python3.12/
                
                # 创建软链接到 /usr/local/bin
                ln -sf /usr/local/python3.12/bin/python3 /usr/local/bin/python3.12
                # python-build-standalone 默认包含 pip3，我们链接它
                if [[ -f /usr/local/python3.12/bin/pip3 ]]; then
                    ln -sf /usr/local/python3.12/bin/pip3 /usr/local/bin/pip3.12
                fi
                
                # 验证是否成功
                if /usr/local/bin/python3.12 --version &>/dev/null; then
                    log_ok "Python ${PY_BIN_VERSION} 预编译版部署成功，耗时仅数秒！"
                    PY_INSTALLED=1
                    mark_result 8 "OK"
                fi
            fi
        fi
        rm -rf "$TMP_PY"
    fi

    # 兜底方案：如果预编译版下载或运行失败，则使用源码编译安装
    if [[ $PY_INSTALLED -eq 0 ]]; then
        log_warn "预编译包部署失败或不支持的架构，正在切换回源码编译模式 (这可能需要 5~15 分钟)..."
        PY_SRC_VERSION="3.12.8"
        PY_SRC_URL="https://www.python.org/ftp/python/${PY_SRC_VERSION}/Python-${PY_SRC_VERSION}.tar.xz"

        log_info "安装编译依赖..."
        apt-get install -y -qq \
            build-essential zlib1g-dev libncurses5-dev libgdbm-dev \
            libnss3-dev libssl-dev libreadline-dev libffi-dev \
            libsqlite3-dev libbz2-dev liblzma-dev \
            >> "$LOG_FILE" 2>&1

        TMP_PY=$(mktemp -d)
        log_info "下载 Python $PY_SRC_VERSION 源码..."

        if wget -q --show-progress --no-check-certificate -O "$TMP_PY/Python.tar.xz" "$PY_SRC_URL" 2>> "$LOG_FILE"; then
            cd "$TMP_PY"
            tar -xf Python.tar.xz >> "$LOG_FILE" 2>&1
            cd "Python-${PY_SRC_VERSION}"

            log_info "配置编译参数 (--enable-optimizations)..."
            ./configure --enable-optimizations --prefix=/usr/local >> "$LOG_FILE" 2>&1

            NPROC=$(nproc 2>/dev/null || echo 2)
            log_info "开始编译 (并行线程: $NPROC)..."
            make -j"$NPROC" >> "$LOG_FILE" 2>&1
            make altinstall >> "$LOG_FILE" 2>&1

            cd /
            rm -rf "$TMP_PY"

            if command -v python3.12 &>/dev/null; then
                log_ok "Python 源码编译安装成功: $(python3.12 --version)"
                python3.12 -m ensurepip --upgrade >> "$LOG_FILE" 2>&1 || true
                python3.12 -m pip install --upgrade pip >> "$LOG_FILE" 2>&1 || true
                mark_result 8 "OK"
            else
                log_err "Python 编译安装后命令不可用"
                mark_result 8 "FAIL"
            fi
        else
            log_err "Python 源码下载失败"
            rm -rf "$TMP_PY"
            mark_result 8 "FAIL"
        fi
    fi
fi

if [[ "${RESULTS[8]:-}" != "FAIL" ]]; then
    TARGET_PY=""
    if command -v python3.12 &>/dev/null; then
        TARGET_PY=$(command -v python3.12)
    elif [[ -n "${PY312_CMD:-}" ]] && command -v "$PY312_CMD" &>/dev/null; then
        TARGET_PY=$(command -v "$PY312_CMD")
    fi

    if [[ -n "$TARGET_PY" ]]; then
        log_info "配置系统默认 python3 和 pip3 指向 $TARGET_PY ..."
        # 创建软链接到 /usr/local/bin
        ln -sf "$TARGET_PY" /usr/local/bin/python3
        
        # 对应链接 pip3
        TARGET_PIP=$(echo "$TARGET_PY" | sed 's/python/pip/g')
        if [[ -x "$TARGET_PIP" ]]; then
            ln -sf "$TARGET_PIP" /usr/local/bin/pip3
        else
            BIN_PIP312=$(command -v pip3.12 || echo "")
            if [[ -n "$BIN_PIP312" ]]; then
                ln -sf "$BIN_PIP312" /usr/local/bin/pip3
            fi
        fi
        log_ok "默认 python3 软链接已配置，当前 python3 -V: $(python3 -V 2>/dev/null || echo 'unknown')"
    fi
fi


# =============================================================================
#  [10/13] 系统监控工具集
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
    mark_result 9 "OK"
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
    mark_result 9 "FAIL"
fi

# =============================================================================
#  [11/13] 硬盘 IO 基准测试 (fio)
# =============================================================================
log_step "安装硬盘 IO 基准测试工具 (fio)"

if command -v fio &>/dev/null; then
    FIO_VER=$(fio --version 2>/dev/null || echo "已安装")
    log_warn "fio 已安装: $FIO_VER，跳过"
    mark_result 10 "SKIP"
else
    log_info "正在安装 fio ..."
    if apt-get install -y -qq fio >> "$LOG_FILE" 2>&1; then
        log_ok "fio 安装成功: $(fio --version 2>/dev/null)"
        log_info "常用基准测试命令:"
        log_info "  顺序读:   fio --name=seqread  --rw=read     --bs=1M --size=1G --numjobs=1 --runtime=30 --group_reporting"
        log_info "  顺序写:   fio --name=seqwrite --rw=write    --bs=1M --size=1G --numjobs=1 --runtime=30 --group_reporting"
        log_info "  随机读写: fio --name=randrw    --rw=randrw  --bs=4K --size=1G --numjobs=4 --runtime=30 --group_reporting"
        mark_result 10 "OK"
    else
        log_err "fio 安装失败"
        mark_result 10 "FAIL"
    fi
fi

# =============================================================================
#  [12/13] FileBrowser — 现代化 HTTP 文件下载服务 (带认证)
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
    mark_result 11 "SKIP"
else
    log_info "使用官方安装脚本安装 FileBrowser..."
    if curl -fsSL -k "${PROXY_PREFIX}https://raw.githubusercontent.com/filebrowser/get/master/get.sh" | bash >> "$LOG_FILE" 2>&1 || \
       (log_warn "首选链接下载 FileBrowser 脚本失败，尝试通过代理镜像下载..." && \
        curl -fsSL -k "https://mirror.ghproxy.com/https://raw.githubusercontent.com/filebrowser/get/master/get.sh" | bash >> "$LOG_FILE" 2>&1); then
        if command -v filebrowser &>/dev/null; then
            FB_VER=$(filebrowser version 2>/dev/null || echo "installed")
            log_ok "FileBrowser 安装成功: $FB_VER"
            mark_result 11 "OK"
        else
            log_err "FileBrowser 安装脚本执行成功但命令不可用"
            mark_result 11 "FAIL"
        fi
    else
        log_err "FileBrowser 安装脚本执行失败"
        mark_result 11 "FAIL"
    fi
fi

# 统一确保 FileBrowser 配置、默认账号和服务正确 (SKIP 和 OK 都会运行，仅在安装没有 FAIL 时)
if [[ "${RESULTS[11]:-}" != "FAIL" ]]; then
    # 创建配置目录和共享目录
    mkdir -p "$(dirname "$FB_DB")" "$FB_ROOT"

    # 如果数据库文件存在但大小为 0（之前安装失败遗留的空文件），删除重建
    if [[ -f "$FB_DB" && ! -s "$FB_DB" ]]; then
        rm -f "$FB_DB"
    fi

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

    # 确保数据库已初始化
    if [[ ! -f "$FB_DB" ]]; then
        filebrowser config init --config "$FB_CONFIG" >> "$LOG_FILE" 2>&1 || true
    fi

    # 统一确保默认管理员账户存在且密码为 admin
    if filebrowser users find admin --config "$FB_CONFIG" &>/dev/null; then
        # 强制重置密码，保证一定能以 admin/admin 登录
        filebrowser users update admin --password admin --config "$FB_CONFIG" >> "$LOG_FILE" 2>&1 || true
        log_ok "管理员账户存在，已重置密码为默认: admin"
    else
        filebrowser users add admin admin --perm.admin --config "$FB_CONFIG" >> "$LOG_FILE" 2>&1 || true
        log_ok "默认管理员账号已成功创建: admin / admin"
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

    # 启动/重启并启用服务
    systemctl daemon-reload >> "$LOG_FILE" 2>&1 || true
    systemctl enable filebrowser >> "$LOG_FILE" 2>&1 || true
    systemctl restart filebrowser >> "$LOG_FILE" 2>&1 || true

    log_info "┌─────────────────────────────────────────────────┐"
    log_info "│  FileBrowser 配置摘要                           │"
    log_info "├─────────────────────────────────────────────────┤"
    log_info "│  Web 地址:   http://<服务器IP>:${FB_PORT}        │"
    log_info "│  共享目录:   ${FB_ROOT}                         │"
    log_info "│  默认账号:   admin / admin                      │"
    log_info "│  启动命令:   systemctl enable --now filebrowser │"
    log_info "│  ⚠️  请首次登录后立即修改默认密码！             │"
    log_info "└─────────────────────────────────────────────────┘"
fi

# =============================================================================
#  [13/13] Docker + Docker Compose 稳定版
# =============================================================================
log_step "安装 Docker CE + Docker Compose 稳定版"

if command -v docker &>/dev/null; then
    DOCKER_VER=$(docker --version 2>/dev/null || echo "已安装")
    log_warn "Docker 已安装: $DOCKER_VER"

    # 检查 Docker Compose (v2 plugin 方式)
    if docker compose version &>/dev/null; then
        COMPOSE_VER=$(docker compose version 2>/dev/null)
        log_warn "Docker Compose 已安装: $COMPOSE_VER，跳过"
        mark_result 12 "SKIP"
    else
        log_info "Docker 已安装但缺少 Compose 插件，将单独安装..."
        apt-get install -y -qq docker-compose-plugin >> "$LOG_FILE" 2>&1 || true
        if docker compose version &>/dev/null; then
            log_ok "Docker Compose 插件安装成功: $(docker compose version)"
            mark_result 12 "OK"
        else
            log_err "Docker Compose 插件安装失败"
            mark_result 12 "FAIL"
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
        curl -fsSL -k https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg >> "$LOG_FILE" 2>&1
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
        if curl -fsSL -k https://get.docker.com | bash >> "$LOG_FILE" 2>&1; then
            log_ok "Docker CE 通过便捷脚本安装成功"
            # 便捷脚本可能不包含 compose 插件，单独安装
            apt-get install -y -qq docker-compose-plugin >> "$LOG_FILE" 2>&1 || true
        else
            log_err "Docker 所有安装方式均失败"
            mark_result 12 "FAIL"
        fi
    fi

    # 最终验证
    if [[ "${RESULTS[12]:-}" != "FAIL" ]]; then
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

            mark_result 12 "OK"
        else
            log_err "Docker 安装后命令不可用"
            mark_result 12 "FAIL"
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
