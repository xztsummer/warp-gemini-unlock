# 🚀 warp-gemini-unlock — VPS Google / Gemini 精准 WARP 分流解锁脚本

<!-- 徽章为本地副本，避免外链依赖；重新生成时取 img.shields.io/badge/ 下同名参数：
     platform-Debian|Ubuntu|RHEL|CentOS-orange、Cloudflare-WARP-f38020、
     隧道-MASQUE|QUIC-3b82f6、分流-sing-box-7c3aed -->
![Platform](assets/badges/platform.svg)
![Cloudflare WARP](assets/badges/cloudflare-warp.svg)
![Tunnel](assets/badges/tunnel-masque-quic.svg)
[![Router](assets/badges/routing-sing-box.svg)](https://github.com/SagerNet/sing-box)

专为 Linux VPS 打造的 **Google 搜索 / Google AI 精准分流解锁方案**。基于 Cloudflare 官方客户端的 **MASQUE（QUIC over 443）本地 SOCKS5 代理**，由 **sing-box** 把目标域名单独送进 WARP，其余流量 **100% 走 VPS 原生网络**。

不把所有流量塞进 WARP 是刻意取舍：YouTube、Google Play 独立 CDN、ChatGPT、Claude 与普通外网访问保持原生直连，解锁的同时不牺牲速度与延迟。

项目名称 `warp-gemini-unlock`，仓库：[github.com/xztsummer/warp-gemini-unlock](https://github.com/xztsummer/warp-gemini-unlock)。全仓库只维护一个脚本 `warp-geimini-masque.sh`：Cloudflare 官方客户端 + MASQUE 本地 SOCKS5 + 自动接入 sing-box，同时提供交互式菜单与命令行子命令。

---

## 🌟 核心特色与技术优势

- 🎯 **最小域名集合**：只把 Google 搜索/核心基础与 Google AI 的根域名交给 MASQUE，其余域名一律直连。
- ⚡ **MASQUE 出口更干净**：官方客户端走 443 端口的 QUIC 通道，由 Cloudflare 自行调度边缘与会话；相比依赖固定 Anycast 接入点的 WireGuard 类方案，更容易落到 Google 判定为干净的出口池。
- 🧠 **拒绝“HTTP 200 即解锁”**：同时校验 `warp=on`、Google 页面内部地区码（不能是 `CHN` / `HKG`）、Gemini 与 AI Studio 的地区限制文案，四项全过才算成功。
- 🔁 **保留注册的出口刷新**：已有官方 WARP 注册先做验收，不合格就断线重连换出口，不删除设备；只注销本轮新建且未通过验收的候选注册。
- 🧪 **生产链路端到端验收**：临时挑一个空闲端口（18080-18120）开 `127.0.0.1` 健康检查入口，让真实 sing-box 走一遍分流，验证通过后才删除入口、写入正式配置。
- 🛡️ **零系统侵入**：代理只监听 `127.0.0.1`，不改系统默认路由、不动 `/etc/resolv.conf`、不写 iptables，不会把 SSH 锁在门外，也不影响 VPS 上其他代理软件。
- 🧹 **改动前必备份，失败必回滚**：每次变更先做时间戳备份，sing-box 配置先 `check` 再重启，端到端验收失败自动恢复原配置。
- 📊 **收尾自动汇总**：安装、刷新、仅修复接入结束后自动打印状态面板，不用再手动查状态。

---

## 📥 一键安装与管理命令

**方式一：一键命令**

```bash
bash <(curl -sL https://raw.githubusercontent.com/xztsummer/warp-gemini-unlock/main/warp-geimini-masque.sh)
```

**方式二：克隆 `warp-gemini-unlock` 仓库后上传**（本次实测用的就是这种方式，见文末「实测记录」）

```bash
git clone https://github.com/xztsummer/warp-gemini-unlock.git
cd warp-gemini-unlock

scp -P 22 ./warp-geimini-masque.sh root@YOUR_VPS:/root/
ssh -p 22 root@YOUR_VPS 'bash /root/warp-geimini-masque.sh install'
```

把 `22`、`YOUR_VPS` 换成实际 SSH 端口和主机。安装器会输出本次备份目录和状态面板。

两种方式都支持在目标 VPS（Debian / Ubuntu / RHEL / CentOS / AlmaLinux / Rocky）上以 `root` 运行。

> **提示**：脚本自带交互式控制台，菜单 `1` / `2` / `5` 执行结束后会自动打印状态面板。

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

自动化场景可以绕过菜单，直接使用子命令：

```bash
sudo bash warp-geimini-masque.sh install      # 智能安装 / 修复
sudo bash warp-geimini-masque.sh refresh      # 保留注册，刷新出口并验收
sudo bash warp-geimini-masque.sh test         # 严格测试当前出口
sudo bash warp-geimini-masque.sh status       # 查看脱敏状态
sudo bash warp-geimini-masque.sh integrate    # 仅修复 sing-box 接入
sudo bash warp-geimini-masque.sh restore /root/warp-google-masque-backup-...  # 恢复备份
sudo bash warp-geimini-masque.sh connect      # 连接 MASQUE
sudo bash warp-geimini-masque.sh disconnect   # 断开 MASQUE
```

非交互环境（如 CI、`ssh host 'bash script'`）直接运行脚本不会卡在菜单，会打印用法后退出。

可选环境变量：

```bash
WARP_PROXY_PORT=40000               # 官方 MASQUE 本地 SOCKS5 端口，1024-65535
WARP_MAX_RETRIES=10                 # 注册轮换 / 出口刷新重试次数，1-30
SINGBOX_CONFIG=/path/sb.json        # 显式指定 sing-box 配置路径
WARP_ALLOW_RECONFIGURE_EXISTING=1   # 允许把已有官方客户端切换为本地代理模式
```

> **sing-box 从哪来**：本脚本只负责把 Google / Gemini 流量交给 MASQUE，不搭建节点。VPS 上还没有 sing-box 时，推荐用 [sing-box-yg](https://github.com/yonggekkk/sing-box-yg) 一键安装，本项目可直接识别它的配置（详见 FAQ）；完全不装 sing-box 也能运行，脚本会保留本地 SOCKS5 入口。

---

## 📋 精准分流域名与服务矩阵

sing-box 使用**根域名后缀规则**：命中某个根域名后，它的所有二级、多级子域名自动生效。

| 业务矩阵 | 覆盖范围与关键说明 | 包含的根域名（下级子域名自动生效） |
| :--- | :--- | :--- |
| **Google 搜索与核心基础** | 搜索主站、前端静态资源、API 总线、CDN 与骨干节点；`google.com` 同时覆盖 `gemini.google.com`、`aistudio.google.com`、`bard.google.com` 等子域 | `google.com`<br>`googleapis.com`<br>`googleusercontent.com`<br>`gstatic.com`<br>`1e100.net`<br>`google-analytics.com`<br>`googletagmanager.com`<br>`goo.gl`<br>`google.dev`<br>`web.dev`<br>`chrome.com` |
| **亚太防跳转域名** | 送中时 Google 常把请求改址到这些地区站；一并分流可避免跳转后落回受限地区 | `google.co.jp`<br>`google.com.hk`<br>`google.com.tw`<br>`google.cn` |
| **Google AI 与 DeepMind** | Gemini 生态工具、NotebookLM、Generative AI 入口与 DeepMind 独立域名 | `antigravity.google`<br>`notebooklm.google`<br>`generativeai.google`<br>`deepmind.com`<br>`deepmind.google` |
| **验收期临时域名** | 只在安装 / 接入阶段临时加入，用于确认请求确实走到 WARP；验收通过后自动从正式配置中移除 | `www.cloudflare.com` |
| **明确不纳入分流** | 保持 VPS 原生直连，速度与延迟不受影响 | `youtube.com`<br>`googlevideo.com`<br>`ytimg.com`<br>`gvt1.com`<br>`ggpht.com`<br>`chatgpt.com`<br>`openai.com`<br>`claude.ai`<br>`anthropic.com` |

---

## 🧪 严格验收标准

只满足“页面 HTTP 200”不判定为解锁成功。脚本要求以下四项同时成立，全部通过才写入正式配置：

1. Cloudflare `cdn-cgi/trace` 必须返回出口 IP，且 `warp=on`。
2. Google 搜索必须 HTTP 200，不跳转 `/sorry/` 或 `google.com.hk`，页面内部地区码必须存在且不是 `CHN`、`HKG`。
3. Gemini 必须 HTTP 200，且不出现地区限制文案或 `BardErrorInfo 1060`。
4. AI Studio 必须 HTTP 200，且不出现地区限制文案。

刷新出口时每一轮都会重跑这四项；首次安装若轮换全部失败，会自动执行本轮备份的 `restore.sh`，避免把服务器留在坏出口上。

四项验收全部通过 TCP 请求（`curl`）完成，因此不覆盖 QUIC / UDP 路径，相关行为见 FAQ。

---

## 🔍 日常状态与流量检测方法

### 1. 一键查看运行状态

```bash
bash /root/warp-geimini-masque.sh status
```

- **解读**：一次输出客户端版本、`warp-svc` 状态、注册与连接状态、工作模式、代理监听、sing-box 分流条数、经 MASQUE 探测的公网出口 IP 与 Google 内部地区码、最近备份目录。面板不显示设备 ID、License、Token 或私钥。

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

- **解读**：`warp=on` 说明该请求确实经过 WARP；`ip=` 是 WARP 出口 IP；`loc=` 是 Cloudflare 视角的国家码。
- **注意**：`loc=US` 只代表 Cloudflare 的判断。若 Google 页面内部地区码是 `CHN` / `HKG`，仍然算未解锁，请以第 3 步为准。

### 3. 严格验收（Google / Gemini / AI Studio 一起测）

```bash
bash /root/warp-geimini-masque.sh test
```

- **解读**：只读操作，不修改注册、工作模式或 sing-box 配置。输出形如：

```text
出口族: IPv4 | WARP: on | CF: US | Google: USA | Google HTTP: 200 | Gemini: 200/block=0 | AI Studio: 200/block=0
```

- `block=1` 表示页面出现了地区限制文案；`Google` 后的三字母就是 Google 自己返回的地区码。

### 4. 检查官方客户端与本地代理监听

```bash
warp-cli --accept-tos --no-ansi status
ss -lntp | grep 40000
```

- **解读**：状态应显示 `Connected`，并且能看到 `127.0.0.1:40000` 处于监听。若未监听，运行菜单 `7` 重新连接，或检查 `warp-cli --accept-tos mode proxy` 与 `proxy port 40000` 是否生效。

### 5. 校验 sing-box 配置与分流规则

```bash
sing-box check -c /etc/s-box/sb.json
jq -r '[.outbounds[]?|select(.tag=="warp-masque")]|length' /etc/s-box/sb.json
jq -r '[.route.rules[]?|select(.outbound=="warp-masque")]|length' /etc/s-box/sb.json
```

- **解读**：语法检查通过，且两条计数各为 `1`，说明 `warp-masque` 出站和域名分流规则都在正式配置里。
- 实际配置路径可能是 `/etc/s-box/sb.json`、`/etc/sing-box/config.json` 或其他位置，安装器会自动探测，也可用 `SINGBOX_CONFIG` 指定。

### 6. 验证未分流域名仍是原生出口

```bash
curl -4 -s ip.sb
```

- **解读**：返回 VPS 本机原生公网 IP，说明 YouTube、Google Play、ChatGPT 等未列出的域名依旧直连，原生速度不受影响。

### 7. 确认自己的客户端流量确实走了 MASQUE

```bash
journalctl -u sing-box.service -f | grep -E 'google|warp-masque'
```

- **解读**：用浏览器打开 `gemini.google.com`，日志里应出现 `inbound/...(你的入站): inbound connection to gemini.google.com:443`，紧随其后是 `outbound/socks[warp-masque]: outbound connection to gemini.google.com:443`，说明客户端流量已按域名分流到 MASQUE。
- 如果只有 inbound 那行、没有 `warp-masque` 那行，多半是入站没有开启域名嗅探（脚本依赖配置里的 `action: sniff` 规则取得域名），此时域名规则无法命中，流量会落到直连。

---

## 🔄 备份、恢复与回滚

每次变更前都会创建独立备份目录（仅 root 可读）：

```text
/root/warp-google-masque-backup-YYYYMMDDTHHMMSSZ.XXXXXX
```

其中包含 Cloudflare 客户端状态、改动前的 sing-box 配置、配置路径记录和独立可执行的 `restore.sh`（`format-version` 为 `2`）。

恢复方式（菜单 `6` 或子命令）：

```bash
bash /root/warp-geimini-masque.sh restore /root/warp-google-masque-backup-YYYYMMDDTHHMMSSZ.XXXXXX
```

- 恢复脚本会还原备份时的 sing-box 配置和 Cloudflare 客户端状态，并**实际检查 WARP 是否重新连通**。
- 若旧注册已在 Cloudflare 服务端失效，它会保留恢复前的客户端状态并报告失败，不会把服务器留在无网状态。
- 它不会卸载新安装的系统软件；当前 Cloudflare 状态会先移动到带时间戳的保留目录。
- `restore` 只接受 `/root/warp-google-masque-backup-*` 路径，并要求备份目录带有格式版本标记（`format-version` 为 `2`，即包含连通性校验）；格式不符的目录会被直接拒绝，不会尝试恢复。

---

## 🛠️ 常见问题解答 (FAQ)

### Q: Cloudflare trace 显示 `loc=US`，为什么 Gemini 还是提示地区不支持？
- `cdn-cgi/trace` 的 `loc` 是 Cloudflare 自己的判断，不代表 Google 也把这个出口认作美国。脚本因此不看 `loc`，而是校验 Google 页面内部地区码、Gemini / AI Studio 的地区限制文案。请在菜单选择 **`[2] 保留注册，刷新 MASQUE 出口并严格验收`**，脚本会断线重连换出口，直到四项验收全部通过或达到重试上限。

### Q: 送中了 / 出口不合格怎么办？
- 同样是菜单 **`[2]`**。刷新是保留官方注册的重连换 IP，不会删除你的设备；只有首次安装时本轮新建且未通过验收的候选注册才会被注销。想加大尝试次数，可以用 `WARP_MAX_RETRIES=20 bash warp-geimini-masque.sh refresh`（上限 30）。

### Q: 为什么不把 YouTube、Google Play、ChatGPT、Claude 一起送进 WARP？
- 本项目刻意只做最小集合。YouTube、Google Play 独立 CDN、OpenAI 与 Anthropic 域名继续走 VPS 原生网络，换来的是原生速度、更低的延迟，以及更少的域名被牵连进 WARP 出口。如果你确实需要扩展，请在 sing-box 配置里自行添加域名规则——脚本只会管理它自己写入的 `warp-masque` 规则，不会覆盖你的其他规则。

### Q: 会不会把自己 SSH 锁在门外？会不会影响 VPS 上的其他代理？
- 不会。方案只做三件事：把官方客户端切到 `proxy` 模式、监听 `127.0.0.1`、在 sing-box 里加一条出站和一条域名规则。它**不改系统默认路由、不改 `/etc/resolv.conf`、不写 iptables/ipset**，所以 SSH 与其他代理软件的流量路径完全不变。

### Q: VPS 上官方 WARP 客户端已经在给别的业务用了（系统代理 / 全隧道），会被改坏吗？
- 默认会保护。脚本检测到已有注册且工作模式不是 `proxy` 时会直接拒绝切换并给出提示。确认要改成仅本机 SOCKS5 代理后，再显式授权：

```bash
WARP_ALLOW_RECONFIGURE_EXISTING=1 bash warp-geimini-masque.sh install
```

- 该操作可能影响依赖现有 WARP 模式的其他应用，请自行确认。

### Q: 服务器没有装 sing-box 会怎样？
- 脚本不会去安装或修改其他代理软件，只会保留一个可用的本地代理入口，你可以在 Xray、V2Ray、其他 sing-box 实例或应用程序里手工把目标域名指向它：

```text
SOCKS5 127.0.0.1:40000
```

- 如果 VPS 上还没有 sing-box，推荐先直接用 **[sing-box-yg](https://github.com/yonggekkk/sing-box-yg)** 一键脚本安装，与本项目兼容：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/sb.sh)
```

- 兼容方式：sing-box-yg 把配置固定放在 `/etc/s-box/sb.json`、以 `sing-box.service` 运行（`ExecStart=/etc/s-box/sing-box run -c /etc/s-box/sb.json`），而这正是本安装器优先探测的路径；探测不到时还会解析 systemd 的 `ExecStart` 反查。装好 sing-box-yg 后运行本脚本的 `install`，它会先备份该配置，再追加 `warp-masque` 出站与 Google / Gemini 域名规则，不改动你已有的出站与其他规则。
- 这一兼容性已在真实的 sing-box-yg 环境（sing-box 1.14.1）验证通过，详见文末「实测记录」。
- 唯一需要注意的是规则顺序：本脚本写入的分流规则排在 `sniff` 规则之后、你其他规则之前。如果你此前已经用 sing-box-yg 的域名分流把 Google 域名指向别的通道，本项目的规则会优先命中；想改回去用菜单 `[6]` 恢复备份即可。
- 检测到 sing-box 配置却找不到 sing-box 可执行文件时，脚本会报错而不是猜测。

### Q: 分流之后，浏览器用 QUIC（HTTP/3）访问 Google 会怎样？
- Cloudflare 官方客户端的本地 SOCKS5 代理**不支持 UDP ASSOCIATE**（实测返回码 `7`），所以被分流的 Google 系域名只能走 TCP。浏览器发现 QUIC 不通会自动回退到 HTTP/2 over TCP，日常使用没有影响，首次加载可能有极短等待。
- 想彻底避开这次回退，可以在浏览器里关闭 QUIC（Chrome 的 `chrome://flags` → Experimental QUIC protocol 设为 Disabled）。
- 本项目的验收测试同样基于 TCP，因此 QUIC 不可用不会影响验收结果。

### Q: 我的 VPS 直连就能打开 Gemini，还需要装吗？
- 不是必须的。如果直连时 Google 页面内部地区码就不是 `CHN` / `HKG`，Gemini 与 AI Studio 也没有地区限制文案，说明这台机器本身就在可服务地区；本方案的价值只在于把 Google 流量固定到 WARP 出口，用来规避机房 IP 被 Google 改判或风控的情况。
- 装与不装取决于你更信任哪个出口；装过之后随时可以用菜单 `[6]` 恢复备份回到安装前状态。

### Q: 卸载或回滚怎么做？
- 回滚用菜单 `[6]` 或 `restore` 子命令，恢复到某次备份之前的状态。希望彻底恢复原生网络时，先执行 `disconnect` 断开并保留注册，再按需移除 sing-box 中的 `warp-masque` 出站与规则（从备份恢复即可一步到位）；官方客户端本体不会被动卸载，需要时自行执行 `systemctl disable --now warp-svc && apt remove cloudflare-warp`。

### Q: 命令行验收通过了，Gemini 网页登录后还是打不开？
- 命令行部分（安装、安装复用、接入、刷新、备份恢复、连接/断开、新 SSH 登录）已实测，最近一次环境与结果见文末「实测记录」。登录态下的 Gemini 浏览器界面涉及账号、Cookie 与前端行为，仍需使用者自行验证；如果自动化测试通过而浏览器仍受限，优先怀疑出口 IP 被 Google 风控，回到菜单 `[2]` 换一个出口。

---

## ✅ 实测记录

在一台 Ubuntu 24.04.3 x86_64 的 VPS 上实测（sing-box 1.14.1，由 sing-box-yg 安装，配置 `/etc/s-box/sb.json`；官方 `warp-cli` 2026.7.1377.0）：

- **首次 `install` 一次通过**：四项验收达标，输出为 `出口族: IPv6 | WARP: on | CF: US | Google: USA | Google HTTP: 200 | Gemini: 200/block=0 | AI Studio: 200/block=0`。
- **再次 `install` 走复用路径**：检出已有注册并验收通过；两次接入后 `warp-masque` 出站与规则各仍为 1 条，没有重复堆积。
- **生产链路确实生效**：sing-box 日志中 `warp-healthcheck` 入站的 `google.com`、`gemini.google.com`、`aistudio.google.com` 请求都由 `outbound/socks[warp-masque]` 发出。
- **现场核对无副作用**：`sing-box check` 通过、`sing-box.service` 保持 active、原有 5 个入站与既有规则未被改动、临时健康检查入口已删除、VPS 原生出口仍是本机 IP（`warp=off`）。
- **未覆盖**：登录态下的 Gemini 浏览器界面，以及 QUIC / UDP 路径（见 FAQ）。

---

## 🔐 安全与注意事项

- 必须以 `root` 运行，因为需要安装软件、管理服务并修改代理配置；仅支持 APT、DNF 或 YUM 系统。
- 备份目录与 sing-box 配置权限会收紧为仅 root 可读（备份目录 `700`，配置 `600`）。
- MASQUE 代理只监听 `127.0.0.1`，不会直接暴露到公网。
- 所有配置改动都先备份、先语法检查、再端到端验收，失败自动回滚。
- 不要把 VPS 密码、SSH 端口、WARP 凭据或完整 sing-box 配置提交到 Git。
