# 🚀 VPS Google / Gemini 精准 WARP 分流解锁脚本

<!-- 徽章为本地 SVG 副本，避免外链依赖 -->
![Platform](assets/badges/platform.svg)
![Cloudflare WARP](assets/badges/cloudflare-warp.svg)
![Tunnel](assets/badges/tunnel-masque-quic.svg)
[![Router](assets/badges/routing-sing-box.svg)](https://github.com/SagerNet/sing-box)

面向 Linux VPS 的 **Google 搜索 / Google AI 精准分流解锁脚本**。它使用 Cloudflare 官方客户端的 **MASQUE（QUIC over 443）本地 SOCKS5 代理**，配合 **sing-box** 的域名规则，只把 Google 搜索与 Google AI 相关域名送进 WARP，其余流量保持 VPS 原生直连。

不把所有流量塞进 WARP 是刻意的取舍：YouTube、Google Play 独立 CDN、ChatGPT、Claude 与普通外网访问继续走原生网络，解锁的同时不牺牲速度与延迟。

安装、切换、验收、回滚全自动：改动前先备份，配置先过语法检查再重启，端到端验收失败自动恢复原状。

---

## ✨ 核心特性

- 🎯 **最小域名集合**：只分流 Google 搜索/核心基础与 Google AI 的根域名，其余域名一律直连。
- ⚡ **MASQUE 出口更干净**：官方客户端走 443 端口的 QUIC 通道，由 Cloudflare 自行调度边缘与会话，比依赖固定 Anycast 接入点的 WireGuard 类方案更容易落到 Google 判定为干净的出口池。
- 🧠 **拒绝“HTTP 200 即解锁”**：同时校验 `warp=on`、Google 页面内部地区码（不能是 `CHN` / `HKG`）、Gemini 与 AI Studio 的地区限制文案，四项全过才算成功。
- 🔁 **保留注册的出口刷新**：已有官方 WARP 注册先做验收，不合格就断线重连换出口，不删除设备；只注销本次新建且未通过验收的候选注册。
- 🧪 **生产链路端到端验收**：临时开一个仅监听回环的健康检查入口，让真实 sing-box 走一遍分流，验证通过后才删除入口、写入正式配置。
- 🛡️ **零系统侵入**：不改系统默认路由、不动 `/etc/resolv.conf`、不写 iptables，也不安装或修改其他代理软件。
- 🧹 **随时可回滚**：每次变更都生成带连通性校验的备份，一条命令恢复改动前的 sing-box 与客户端状态。
- 📊 **收尾自动汇总**：安装、刷新、仅修复接入结束后自动打印状态面板。

---

## 🧩 工作原理

```text
客户端（vless / vmess / hysteria2 / tuic / anytls 等入站）
        │
        ▼
     sing-box ── 命中 google.com、gemini 等域名 ──► SOCKS5 127.0.0.1:40000
        │                                                    │
        │                                            官方 cloudflare-warp
        │                                          （MASQUE / QUIC over 443）
        ▼                                                    │
  其他域名 ──► VPS 原生出口                             Cloudflare WARP ──► Google
```

1. 安装官方 `cloudflare-warp` 客户端，切换为 **MASQUE + 仅监听本机的 SOCKS5 代理**模式。
2. 按「验收标准」筛选出口，合格后写入 sing-box。
3. sing-box 新增一条 `warp-masque` 出站和一条域名分流规则：域名命中走 WARP，其余照旧。

---

## 📋 环境要求

| 项目 | 要求 |
| :--- | :--- |
| 系统 | Ubuntu、Debian、RHEL / CentOS / AlmaLinux / Rocky（APT、DNF 或 YUM 任一） |
| 权限 | `root` |
| sing-box | 可选。已有则自动接入；没有则脚本只提供本地 SOCKS5 入口 |
| 依赖 | `curl`、`jq`（脚本自动安装） |

---

## 📥 安装

**方式一：一键命令**

```bash
bash <(curl -sL https://raw.githubusercontent.com/xztsummer/warp-gemini-unlock/main/warp-geimini-masque.sh)
```

**方式二：克隆仓库后上传**

```bash
git clone https://github.com/xztsummer/warp-gemini-unlock.git
cd warp-gemini-unlock

scp -P 22 ./warp-geimini-masque.sh root@YOUR_VPS:/root/
ssh -p 22 root@YOUR_VPS 'bash /root/warp-geimini-masque.sh install'
```

把 `22`、`YOUR_VPS` 换成实际 SSH 端口和主机。安装结束后会打印备份目录和状态面板。

---

## 🎛 使用

直接运行脚本进入交互菜单：

```bash
bash /root/warp-geimini-masque.sh
```

| 菜单 | 功能 |
| :--- | :--- |
| `1` | 智能安装 / 修复：验收已有注册 → 必要时重连筛选出口 → 接入 sing-box |
| `2` | 保留官方注册，重连刷新 MASQUE 出口 IP 并严格验收（要求新 IP 与刷新前不同） |
| `3` | 严格测试当前 Google / Gemini / AI Studio（只读，不改注册、模式与配置） |
| `4` | 查看脱敏运行状态与最近备份 |
| `5` | 仅修复 sing-box 精准分流接入（要求当前出口已通过严格测试） |
| `6` | 从时间戳备份目录恢复 |
| `7` | 连接 MASQUE |
| `8` | 断开 MASQUE（保留注册与分流配置） |
| `0` | 退出 |

自动化场景可以绕过菜单：

```bash
sudo bash warp-geimini-masque.sh install      # 智能安装 / 修复
sudo bash warp-geimini-masque.sh refresh      # 保留注册，刷新出口并验收
sudo bash warp-geimini-masque.sh test         # 严格测试当前出口
sudo bash warp-geimini-masque.sh status       # 查看脱敏状态
sudo bash warp-geimini-masque.sh integrate    # 仅修复 sing-box 接入
sudo bash warp-geimini-masque.sh restore /root/warp-google-masque-backup-...   # 恢复备份
sudo bash warp-geimini-masque.sh connect      # 连接 MASQUE
sudo bash warp-geimini-masque.sh disconnect   # 断开 MASQUE
```

非交互环境（CI、`ssh host 'bash script.sh install'`）不会卡在菜单：不带子命令运行时打印用法后退出。

可选环境变量：

```bash
WARP_PROXY_PORT=40000               # 官方 MASQUE 本地 SOCKS5 端口，1024-65535
WARP_MAX_RETRIES=10                 # 注册轮换 / 出口刷新重试次数，1-30
SINGBOX_CONFIG=/path/sb.json        # 显式指定 sing-box 配置路径
WARP_ALLOW_RECONFIGURE_EXISTING=1   # 允许把已有官方客户端切换为本地代理模式
```

sing-box 未安装时，脚本不会去安装或修改其他代理软件，只保留一个可用的本地入口（`SOCKS5 127.0.0.1:40000`），可自行接入 Xray、V2Ray 或其他 sing-box 实例。推荐用 [sing-box-yg](https://github.com/yonggekkk/sing-box-yg) 一键安装 sing-box，本项目可直接识别它的配置：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/sb.sh)
```

---

## 🌐 分流域名

sing-box 使用**根域名后缀规则**，命中某个根域名后，它的所有二级、多级子域名自动生效。

| 业务矩阵 | 覆盖范围 | 包含的根域名（下级子域名自动生效） |
| :--- | :--- | :--- |
| **Google 搜索与核心基础** | 搜索主站、前端静态资源、API 总线、CDN 与骨干节点；`google.com` 同时覆盖 `gemini.google.com`、`aistudio.google.com`、`bard.google.com` 等子域 | `google.com`<br>`googleapis.com`<br>`googleusercontent.com`<br>`gstatic.com`<br>`1e100.net`<br>`google-analytics.com`<br>`googletagmanager.com`<br>`goo.gl`<br>`google.dev`<br>`web.dev`<br>`chrome.com` |
| **亚太防跳转域名** | 送中时 Google 常把请求改址到这些地区站，一并分流可避免跳转后落回受限地区 | `google.co.jp`<br>`google.com.hk`<br>`google.com.tw`<br>`google.cn` |
| **Google AI 与 DeepMind** | Gemini 生态工具、NotebookLM、Generative AI 入口与 DeepMind 独立域名 | `antigravity.google`<br>`notebooklm.google`<br>`generativeai.google`<br>`deepmind.com`<br>`deepmind.google` |
| **验收期临时域名** | 只在安装 / 接入阶段临时加入，用于确认请求确实走到 WARP，验收通过后自动移除 | `www.cloudflare.com` |
| **不纳入分流** | 保持 VPS 原生直连 | `youtube.com`<br>`googlevideo.com`<br>`ytimg.com`<br>`gvt1.com`<br>`ggpht.com`<br>`chatgpt.com`<br>`openai.com`<br>`claude.ai`<br>`anthropic.com` |

需要扩展时，直接在 sing-box 里自行添加域名规则即可；脚本只管理自己写入的 `warp-masque` 出站与规则，不会覆盖其他规则。

---

## 🧪 验收标准

只满足“页面 HTTP 200”不判定为解锁成功。脚本要求以下四项同时成立，全部通过才写入正式配置：

1. Cloudflare `cdn-cgi/trace` 必须返回出口 IP，且 `warp=on`。
2. Google 搜索必须 HTTP 200，不跳转 `/sorry/` 或 `google.com.hk`，页面内部地区码必须存在且不是 `CHN`、`HKG`。
3. Gemini 必须 HTTP 200，且不出现地区限制文案或 `BardErrorInfo 1060`。
4. AI Studio 必须 HTTP 200，且不出现地区限制文案。

刷新出口时每一轮都会重跑这四项；首次安装若轮换全部失败，会自动执行本次备份的 `restore.sh`，避免把服务器留在坏出口上。

四项验收都通过 TCP 请求（`curl`）完成，不覆盖 QUIC / UDP 路径，相关行为见 FAQ。

---

## 🔍 状态检查与排错

### 1. 一键查看运行状态

```bash
bash /root/warp-geimini-masque.sh status
```

输出客户端版本、`warp-svc` 状态、注册与连接状态、工作模式、代理监听、sing-box 分流条数、经 MASQUE 探测的出口 IP 与 Google 内部地区码、最近备份目录。面板不显示设备 ID、License、Token 或私钥：

```text
========================================================
Cloudflare WARP MASQUE 状态
========================================================
客户端版本: 2026.x.x
warp-svc:   active / enabled
注册状态:   已注册
连接状态:   Connected
工作模式:   proxy / MASQUE / SOCKS5 127.0.0.1:40000
代理监听:   正常
sing-box:   active / 配置 /etc/s-box/sb.json
精准分流:   出站 1 条，规则 1 条
MASQUE 公网出口（经代理探测）：
  远程解析: 104.x.x.x
  IPv4 探测: 104.x.x.x
Google 经 MASQUE 访问: HTTP 200 / 内部地区 USA
最近备份:   /root/warp-google-masque-backup-20260923T...
========================================================
```

### 2. 确认流量真的走了 WARP

```bash
curl -s --socks5-hostname 127.0.0.1:40000 https://www.cloudflare.com/cdn-cgi/trace | grep -E '^(ip|loc|colo|warp)='
```

`warp=on` 说明请求确实经过 WARP，`ip=` 是 WARP 出口 IP，`loc=` 是 Cloudflare 视角的国家码。注意 `loc=US` 只代表 Cloudflare 的判断：若 Google 页面内部地区码是 `CHN` / `HKG`，仍然算未解锁，请以第 3 步为准。

### 3. 严格验收（Google / Gemini / AI Studio 一起测）

```bash
bash /root/warp-geimini-masque.sh test
```

只读操作，不修改注册、工作模式或 sing-box 配置。输出形如：

```text
出口族: IPv4 | WARP: on | CF: US | Google: USA | Google HTTP: 200 | Gemini: 200/block=0 | AI Studio: 200/block=0
```

`block=1` 表示页面出现了地区限制文案；`Google` 后的三字母是 Google 返回的地区码。

### 4. 检查官方客户端与本地代理监听

```bash
warp-cli --accept-tos --no-ansi status
ss -lntp | grep 40000
```

状态应显示 `Connected`，并且能看到 `127.0.0.1:40000` 处于监听。若未监听，运行菜单 `7` 重新连接，或检查 `warp-cli --accept-tos mode proxy` 与 `proxy port 40000` 是否生效。

### 5. 校验 sing-box 配置与分流规则

```bash
sing-box check -c /etc/s-box/sb.json
jq -r '[.outbounds[]?|select(.tag=="warp-masque")]|length' /etc/s-box/sb.json
jq -r '[.route.rules[]?|select(.outbound=="warp-masque")]|length' /etc/s-box/sb.json
```

语法检查通过，且两条计数各为 `1`，说明 `warp-masque` 出站和域名分流规则都在正式配置里。实际配置路径可能是 `/etc/s-box/sb.json`、`/etc/sing-box/config.json` 或其他位置，安装器会自动探测，也可用 `SINGBOX_CONFIG` 指定。

### 6. 验证未分流域名仍是原生出口

```bash
curl -4 -s ip.sb
```

返回 VPS 本机原生公网 IP，说明 YouTube、Google Play、ChatGPT 等未列出的域名依旧直连。

### 7. 确认客户端流量走了 MASQUE

```bash
journalctl -u sing-box.service -f | grep -E 'google|warp-masque'
```

用浏览器打开 `gemini.google.com`，日志里应出现 `inbound/...(你的入站): inbound connection to gemini.google.com:443`，紧随其后是 `outbound/socks[warp-masque]: outbound connection to gemini.google.com:443`。若只有 inbound 那行，多半是入站没有开启域名嗅探（脚本依赖配置里的 `action: sniff` 规则取得域名），此时域名规则无法命中，流量会落到直连。

---

## 🔄 备份与恢复

每次变更前都会创建独立备份目录（仅 root 可读）：

```text
/root/warp-google-masque-backup-YYYYMMDDTHHMMSSZ.XXXXXX
```

其中包含 Cloudflare 客户端状态、改动前的 sing-box 配置、配置路径记录，以及独立可执行的 `restore.sh`。

```bash
bash /root/warp-geimini-masque.sh restore /root/warp-google-masque-backup-YYYYMMDDTHHMMSSZ.XXXXXX
```

- 恢复时会实际检查 WARP 是否重新连通；若旧注册已在 Cloudflare 服务端失效，会保留恢复前的客户端状态并报告失败，不会把服务器留在无网状态。
- 不会卸载新安装的系统软件；当前 Cloudflare 状态会先移动到带时间戳的保留目录。
- `restore` 只接受 `/root/warp-google-masque-backup-*` 路径，并要求备份目录带有格式版本标记（`format-version` 为 `2`，即包含连通性校验）；格式不符的目录会被直接拒绝。

---

## 🛠 常见问题 (FAQ)

### Q: Cloudflare trace 显示 `loc=US`，为什么 Gemini 还是提示地区不支持？

`cdn-cgi/trace` 的 `loc` 是 Cloudflare 自己的判断，不代表 Google 也把这个出口认作美国。脚本因此不看 `loc`，而是校验 Google 页面内部地区码与 Gemini / AI Studio 的地区限制文案。在菜单选择 **`[2]`**，脚本会断线重连换出口，直到四项验收全部通过或达到重试上限。

### Q: 送中了 / 出口不合格怎么办？

同样是菜单 **`[2]`**。刷新是保留官方注册的重连换 IP，不会删除你的设备；只有首次安装时本次新建且未通过验收的候选注册才会被注销。想加大尝试次数：`WARP_MAX_RETRIES=20 bash warp-geimini-masque.sh refresh`（上限 30）。

### Q: 为什么不把 YouTube、Google Play、ChatGPT、Claude 一起送进 WARP？

本项目刻意只做最小集合，让这些域名继续走 VPS 原生网络，换来原生速度、更低延迟，以及更少的域名被牵连进 WARP 出口。需要扩展时，请在 sing-box 配置里自行添加域名规则——脚本只管理自己写入的 `warp-masque` 规则，不会覆盖你的其他规则。

### Q: 会不会把自己 SSH 锁在门外？会不会影响 VPS 上的其他代理？

不会。方案只做三件事：把官方客户端切到 `proxy` 模式、监听 `127.0.0.1`、在 sing-box 里加一条出站和一条域名规则。它不改系统默认路由、不改 `/etc/resolv.conf`、不写 iptables，SSH 与其他代理软件的流量路径完全不变。

### Q: VPS 上官方 WARP 客户端已经在给别的业务用了（系统代理 / 全隧道），会被改坏吗？

默认会保护：检测到已有注册且工作模式不是 `proxy` 时会直接拒绝切换并给出提示。确认要改成仅本机 SOCKS5 代理后，再显式授权：

```bash
WARP_ALLOW_RECONFIGURE_EXISTING=1 bash warp-geimini-masque.sh install
```

该操作可能影响依赖现有 WARP 模式的其他应用。

### Q: 服务器没有装 sing-box 会怎样？

脚本不会安装或修改其他代理软件，只保留 `SOCKS5 127.0.0.1:40000`，可以手工接入 Xray、V2Ray 或其他 sing-box 实例。若还没有 sing-box，推荐用 [sing-box-yg](https://github.com/yonggekkk/sing-box-yg) 一键安装：它把配置固定在 `/etc/s-box/sb.json`、以 `sing-box.service` 运行（`ExecStart=/etc/s-box/sing-box run -c /etc/s-box/sb.json`），正是本安装器优先探测的路径；探测不到时还会解析 systemd 的 `ExecStart` 反查。装好后运行 `install`，脚本会先备份该配置，再追加 `warp-masque` 出站与域名规则，不改动已有出站与其他规则。

### Q: 通过分流后，浏览器用 QUIC（HTTP/3）访问 Google 会怎样？

Cloudflare 官方客户端的本地 SOCKS5 代理不支持 UDP ASSOCIATE（实测返回码 `7`），被分流的 Google 系域名只能走 TCP。浏览器发现 QUIC 不通会自动回退到 HTTP/2 over TCP，日常使用没有影响，首次加载可能有极短等待。想彻底避开这次回退，可以在浏览器里关闭 QUIC（Chrome 的 `chrome://flags` → Experimental QUIC protocol 设为 Disabled）。

### Q: 我的 VPS 直连就能打开 Gemini，还需要装吗？

不是必须的。如果直连时 Google 页面内部地区码不是 `CHN` / `HKG`，Gemini 与 AI Studio 也没有地区限制文案，说明这台机器本身就在可服务地区；本方案的价值在于把 Google 流量固定到 WARP 出口，规避机房 IP 被 Google 改判或风控的情况。装过之后随时可以用菜单 `[6]` 恢复备份回到安装前状态。

### Q: 验收通过，但 Gemini 网页登录后还是打不开？

脚本的验收基于未登录页面与 TCP 请求；登录态下的界面还受账号、Cookie 与前端行为影响。若验收通过而浏览器仍受限，优先怀疑出口 IP 被 Google 风控，回到菜单 `[2]` 换一个出口。

### Q: 卸载或回滚怎么做？

回滚用菜单 `[6]` 或 `restore` 子命令。想彻底恢复原生网络：先 `disconnect` 断开并保留注册，再按需移除 sing-box 中的 `warp-masque` 出站与规则（从备份恢复即可一步到位）；官方客户端本体不会被动卸载，需要时自行执行 `systemctl disable --now warp-svc && apt remove cloudflare-warp`。

---

## 🔐 安全说明

- 需要以 `root` 运行：安装软件、管理服务、修改代理配置。
- MASQUE 代理只监听 `127.0.0.1`，不会暴露到公网。
- 备份目录权限为 `700`，sing-box 配置为 `600`，仅 root 可读。
- 改动前一律备份，配置先做语法检查再重启，端到端验收失败自动回滚。
- 不修改系统默认路由、DNS 与防火墙，也不安装或改动其他代理软件。

---

## ✅ 兼容性与验证

已在以下环境完整验证：

| 项目 | 版本 / 说明 |
| :--- | :--- |
| 系统 | Ubuntu 24.04.3 x86_64 |
| sing-box | 1.14.1，由 sing-box-yg 安装（`/etc/s-box/sb.json`、`/etc/s-box/sing-box`、`sing-box.service`） |
| Cloudflare 客户端 | warp-cli 2026.7.1377.0 |

- **安装与重复安装**均通过四项验收，典型输出：`出口族: IPv6 | WARP: on | CF: US | Google: USA | Google HTTP: 200 | Gemini: 200/block=0 | AI Studio: 200/block=0`。
- **生产链路生效**：sing-box 日志中 `google.com`、`gemini.google.com`、`aistudio.google.com` 的请求均由 `outbound/socks[warp-masque]` 发出。
- **无副作用**：`sing-box check` 通过、服务保持 active、原有入站与规则未被改动、临时健康检查入口已删除、VPS 原生出口仍为本机 IP（`warp=off`）。
- **未覆盖**：登录态下的 Gemini 浏览器界面，以及 QUIC / UDP 路径（见 FAQ）。
