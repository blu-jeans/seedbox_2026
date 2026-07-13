# 🚀 Seedbox 一键初始化脚本

> **适用系统**: Debian 11 (Bullseye) 及后续稳定版 (Debian 12 Bookworm 等)  
> **CPU 架构**: x86_64 / aarch64  
> **作者**: hyq &nbsp;|&nbsp; **版本**: 2026-07-01

一条命令完成 Seedbox 服务器从裸机到生产就绪的全部初始化，告别逐行手敲的低效时代。

---

## ✨ 核心特性

| 特性 | 说明 |
|------|------|
| **一键执行** | 单脚本、零交互，从裸机到就绪全自动 |
| **幂等安全** | 每步执行前检测，重复运行不会重复写入或覆盖已有配置 |
| **彩色日志** | 终端实时输出：🟢 成功 / 🔴 失败 / 🟡 跳过 / 🔵 信息 |
| **文件日志** | 全量日志自动归档至 `/var/log/seedbox_setup/` |
| **汇总报告** | 执行结束后打印 13 步表格总览 + 成功/失败/跳过计数 |
| **智能兜底** | 关键组件提供多安装源自动 Fallback（如 Docker、FileBrowser） |

---

## 📦 安装清单 (13 步)

| # | 组件 | 说明 |
|---|------|------|
| 1 | **IPv4 优先** | 写入 `gai.conf`，双栈服务器优先走 IPv4（PT Tracker 兼容性） |
| 2 | **基础工具** | `lrzsz` `unzip` `vim` `fuse` `curl` `wget` `git` `build-essential` |
| 3 | **RAR** | 从 rarlab.com 下载最新稳定版，安装 `rar` + `unrar` |
| 4 | **VIM 模版** | 部署自定义 `.vimrc` + `.vim/` 经典配置 |
| 5 | **时区** | 固定为 `Asia/Shanghai` 北京时间，同步硬件时钟 |
| 6 | **inotify 限制** | `max_user_watches` 提升至 4194304，`max_user_instances` 提升至 524288 |
| 7 | **wondershaper** | 网卡限速工具，全局可用 `wondershaper` 命令 |
| 8 | **rclone** | 官方稳定版，云存储同步/挂载瑞士军刀 |
| 9 | **Python 3.12** | 源码编译 `altinstall`（不覆盖系统 Python），含 pip3 |
| 10 | **系统监控工具集** | `nload` `iftop` `htop` `ncdu` `iotop` |
| 11 | **fio** | 硬盘 IO 基准测试工具 |
| 12 | **FileBrowser** | 现代化 Web 文件管理器，内置账号密码认证 |
| 13 | **Docker** | Docker CE + Docker Compose v2 插件 |

---

## 🏁 快速开始

### 1. 上传脚本到服务器

```bash
# 方式A: scp 上传
scp seedbox_setup.sh root@your-server:/root/

# 方式B: 服务器上直接下载
wget https://raw.githubusercontent.com/blu-jeans/seedbox_2026/main/seedbox_setup.sh
```

### 2. 赋权并执行

```bash
chmod +x seedbox_setup.sh
sudo ./seedbox_setup.sh
```

### 3. 等待执行完毕

脚本会逐步输出彩色进度日志，最终打印汇总报告：

```
╔══════════════════════════════════════════════════════════════╗
║               📊  安装结果汇总报告                         ║
╠══════════════════════════════════════════════════════════════╣
  [ 1/13]  IPv4 优先                   ✅ 成功
  [ 2/13]  基础工具                    ✅ 成功
  [ 3/13]  RAR 最新稳定版              ✅ 成功
  ...
  [13/13]  Docker + Compose            ✅ 成功
╠══════════════════════════════════════════════════════════════╣
  成功: 13    失败: 0    跳过: 0
╠══════════════════════════════════════════════════════════════╣
  完成时间: 2026-07-01 16:30:45 CST
  详细日志: /var/log/seedbox_setup/setup_20260701_163000.log
╚══════════════════════════════════════════════════════════════╝
```

---

## ✅ 安装后验证方案

脚本执行完毕后，可逐项运行以下命令确认各组件状态。

### 基础环境验证

```bash
# 时区
date                          # 应显示 CST 时区
timedatectl | grep "Time zone"  # 应输出 Asia/Shanghai

# IPv4 优先
grep "precedence.*::ffff" /etc/gai.conf
# 期望输出: precedence  ::ffff:0:0/96   100

# inotify 限制
cat /proc/sys/fs/inotify/max_user_watches     # 应为 4194304
cat /proc/sys/fs/inotify/max_user_instances   # 应为 524288

# 基础工具
vim --version | head -1
rar 2>&1 | head -1
unrar 2>&1 | head -1
curl --version | head -1
```

### 系统监控验证

```bash
# 实时网速监控 (Ctrl+C 退出)
nload

# 按连接维度查看带宽 (需指定网卡)
iftop -i eth0

# 交互式进程/CPU/内存监控
htop

# 交互式磁盘空间分析
ncdu /

# 磁盘 IO 进程监控
iotop

# 快速总览命令
df -hT          # 磁盘空间
free -h         # 内存使用
uptime          # 运行时间与负载
```

### 硬盘 IO 基准测试

```bash
# 顺序读测试
fio --name=seqread --rw=read --bs=1M --size=1G --numjobs=1 --runtime=30 --group_reporting

# 顺序写测试
fio --name=seqwrite --rw=write --bs=1M --size=1G --numjobs=1 --runtime=30 --group_reporting

# 4K 随机读写 (模拟实际场景)
fio --name=randrw --rw=randrw --bs=4K --size=1G --numjobs=4 --runtime=30 --group_reporting
```

### wondershaper 限速验证

```bash
# 查看帮助
wondershaper --help

# 限速示例: 将 enp4s0 网卡限制为 下载 8Mbps / 上传 8Mbps
wondershaper -a enp4s0 -d 8192 -u 8192

# 查看当前限速规则
wondershaper -s -a enp4s0

# 清除限速
wondershaper -c -a enp4s0
```

### rclone 验证

```bash
rclone --version
# 配置远程存储
rclone config
```

### Python 3.12 验证

```bash
python3.12 --version          # Python 3.12.8
python3.12 -m pip --version   # pip 版本

# 测试安装第三方包
python3.12 -m pip install requests
python3.12 -c "import requests; print(requests.__version__)"
```

### FileBrowser 验证

```bash
# 查看版本
filebrowser version

# 启动服务
systemctl enable --now filebrowser

# 检查运行状态
systemctl status filebrowser

# 访问 WebUI
# http://<服务器IP>:8081
# 默认账号: admin / admin (⚠️ 首次登录后立即修改密码！)
```

**FileBrowser 常用管理命令：**

```bash
# 修改共享根目录 (编辑配置文件)
vim /etc/filebrowser/.filebrowser.json
# 将 "root" 字段改为你的目标目录，例如 "/data/downloads"

# 修改监听端口
# 编辑 .filebrowser.json 中的 "port" 字段

# 命令行添加用户
filebrowser users add 用户名 密码 --config /etc/filebrowser/.filebrowser.json

# 重启服务使配置生效
systemctl restart filebrowser
```

### Docker + Docker Compose 验证

```bash
# Docker 版本
docker --version

# Docker Compose 版本 (v2 插件模式)
docker compose version

# Docker 引擎状态
systemctl status docker

# 运行测试容器
docker run --rm hello-world

# Compose 快速测试
mkdir -p /tmp/docker-test && cd /tmp/docker-test
cat > docker-compose.yml << 'EOF'
services:
  web:
    image: nginx:alpine
    ports:
      - "9090:80"
EOF
docker compose up -d
curl -s http://localhost:9090 | head -5    # 应返回 nginx 欢迎页
docker compose down
rm -rf /tmp/docker-test
```

---

## 📂 目录结构说明

脚本安装后在服务器上产生的关键路径：

```
/var/log/seedbox_setup/              # 安装日志归档目录
├── setup_20260701_163000.log        # 带时间戳的详细日志

/usr/local/bin/
├── rar                              # RAR 压缩工具
├── unrar                            # RAR 解压工具
└── filebrowser                      # FileBrowser 二进制

/opt/wondershaper/                   # wondershaper 仓库目录

/etc/filebrowser/
├── .filebrowser.json                # FileBrowser 配置文件
└── filebrowser.db                   # FileBrowser 用户数据库

/srv/filebrowser/                    # FileBrowser 默认共享目录

/etc/systemd/system/
└── filebrowser.service              # FileBrowser systemd 服务

/root/
├── .vimrc                           # 自定义 VIM 配置
└── .vim/                            # VIM 插件/模版目录
```

---

## 🔧 服务端口速查

| 服务 | 端口 | 默认账号 | 用途 |
|------|------|----------|------|
| FileBrowser | `8081` | admin / admin | HTTP 文件下载 |

> ⚠️ **安全提示**: Web 服务默认密码为 `admin`，**请首次登录后立即修改**。生产环境建议配合 Nginx 反向代理 + SSL 证书使用。

---

## 📋 日志与排错

```bash
# 查看最近一次安装的完整日志
ls -lt /var/log/seedbox_setup/ | head -2
cat /var/log/seedbox_setup/setup_<时间戳>.log

# 查看某个服务的实时日志
journalctl -u filebrowser -f
journalctl -u docker -f
```

**常见问题：**

| 问题 | 排查方向 |
|------|----------|
| FileBrowser 无法访问 | `systemctl status filebrowser`，检查 8081 端口 |
| Docker 启动失败 | `journalctl -u docker --no-pager`，检查内核版本 |
| Python 编译耗时过长 | 正常现象，`--enable-optimizations` 约需 5~15 分钟 |
| RAR 下载 404 | rarlab.com 可能更新了版本号，修改脚本中的 URL |
| wondershaper 命令不存在 | 运行 `ls -la /usr/local/sbin/wondershaper /usr/local/bin/wondershaper` 检查符号链接 |

---

## 🔄 脚本扩展指南

如需新增安装步骤，只需三步：

**1. 修改计数器和名称数组（脚本顶部）：**

```bash
TOTAL_STEPS=14          # 13 → 14

STEP_NAMES=(
    ...
    "新工具名称"          # 新增一行
)
```

**2. 在汇总报告之前添加安装段落：**

```bash
# =============================================================================
#  [14/14] 新工具
# =============================================================================
log_step "安装新工具"

if command -v newtool &>/dev/null; then
    log_warn "新工具已安装，跳过"
    mark_result 13 "SKIP"    # 索引 = 步骤号 - 1
else
    # ... 安装逻辑 ...
    if 安装成功; then
        mark_result 13 "OK"
    else
        mark_result 13 "FAIL"
    fi
fi
```

**3. 重复运行脚本测试** — 幂等设计确保已安装的步骤自动跳过。

---

## 📜 许可证

本脚本仅供个人服务器运维使用。所安装的各组件遵循其各自的开源许可协议。
