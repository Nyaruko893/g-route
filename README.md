# G-ROUTE v3 // Google 生态送中与全链路分流体检仪

> 对标“Google 专属、反焦虑版 IPQuality”：以 **零依赖并发 CLI 为真值探针与分流雷达**，支持 **本地直接离线生成矢量 SVG 与 Windows 原生 PNG**（彻底无需打开网页），同时配套 **Cloudflare Workers Static Assets 精工体检卡与双卡 Diff 台**，全程守住 **永久 $0 成本、零提权、零读磁盘配置、服务端零落库、零隐私上传**。

## 核心亮点 (V3)

1. **零门槛全局交互入口**：无参数直跑展示 1 屏紧凑菜单（零发包前先选模式或看安全审计，直接回车跑极速纯黑盒）；跑完后支持**免重跑快捷动作**（按 `S` 本地存 SVG / Windows 按 `P` 本地存 PNG / 按 `R` 补查本机代理分组）。带任何参数或非交互管道自动跳过菜单。
2. **两层自动环境识别**：
   - **Layer 1（默认常开，纯被动只读）**：自动识别 `本机 TUN · Fake-IP`、`本机 TUN · Real-IP`（只读虚拟网卡名）、`系统代理`、`上游透明代理 / 旁路由` 与 `直连出站`。
   - **Layer 2（可选 `--inspect` / `-Inspect`）**：按公开白名单自动发现 Clash Verge Rev / Mihomo Party / Nyanpasu / sing-box 的命名管道、Unix Socket 或 `127.0.0.1:9090/9097/9095`（遇 401 现场提示密钥），并行审计 **15 个 Google AI & 跨 AI 关键域名**（含 `generativelanguage.googleapis.com`、`alkalimakersuite-pa.clients6.google.com`、`oauth2.googleapis.com`、`accounts.google.com`），绝不扫进程名、绝不读 `%APPDATA%` 磁盘文件。
3. **并发 6 桶分流拓扑雷达（4–6 秒出卡）**：并行探测国内直连、通用海外、Google/YT GGC、Cloudflare、OpenAI (ChatGPT) 与 Anthropic (Claude) 实见出口，自动聚合成 `[出口 A/B/C]`，附各桶 RTT、WARP 标记与 4 类自动化分流暗坑告警。
4. **本地 100% 离线出图（免去网页后患）**：跨平台零依赖纯文本直出高清矢量 `.svg`（支持 `--theme light|dark`，默认严格隐藏本机节点名），Windows 端同步支持系统内置 `.NET System.Drawing` 零依赖直出 2x `.png`。

## 快速开始

### 1. 一行命令启动（默认进入 1 屏交互菜单，回车即跑）
- **Linux / macOS / VPS（GitHub Raw）**：
  ```bash
  bash <(curl -sL https://raw.githubusercontent.com/Nyaruko893/g-route/main/scripts/check.sh)
  ```
- **Windows PowerShell (5.1 & 7)**：
  ```powershell
  irm https://raw.githubusercontent.com/Nyaruko893/g-route/main/scripts/check.ps1 | iex
  ```
- **部署到 Cloudflare Workers 后的短链**：
  - Linux / macOS / VPS：`bash <(curl -sL https://<your-worker>.workers.dev/sh)`
  - Windows PowerShell：`irm https://<your-worker>.workers.dev/ps | iex`

### 2. 常用直通参数（跳过菜单直跑）
- `--quick` / `-Quick`：跳过交互菜单直接执行纯黑盒体检
- `--inspect` / `-Inspect`（或环境变量 `G_ROUTE_INSPECT=1`）：白名单自动发现本机 Mihomo / sing-box 控制口并审计 15 域规则一致性
- `--controller <url|pipe|sock>` / `-Controller`（配 `--secret` / `-Secret`）：显式指定本地控制口，仅本屏只读展示，绝不写入 `#r=` 或默认 SVG/PNG
- `--svg [path]` / `-Svg [path]`：本地 100% 离线生成高清矢量 SVG 体检卡（配 `--theme dark` / `--with-rules`）
- `-Png [path]`（Windows）：零依赖调用内置 `.NET` 本地直出 2x 高清 PNG
- `--dry-run` / `-DryRun`：零发包安全审计，打印全部只读请求域名与权限边界后立即退出
- `--ascii` / `--compact` / `NO_COLOR=1`：老旧终端与窄屏兼容选项
- `-4` / `-6`（`-V4` / `-V6`）、`-f`（`-Full`）、`-x <proxy>`（`-Proxy`）、`-j`（`-Json`）、`--no-link`（`-NoLink`）

### 3. 权限边界契约（4 个绝不）
1. 绝不申请管理员 / UAC / `sudo` 提权；
2. 绝不读取磁盘配置文件（`~/.ssh`、`%APPDATA%` 代理订阅、浏览器 Cookie）或枚举进程；
3. 绝不向任何服务器上传检测结果（`#r=`、本地 SVG 与本地 PNG 均 100% 离线生成，默认 IP 脱敏）；
4. 绝不下载二进制文件或执行混淆密文；网页启动台内置实时源码审阅器与浏览器端 `SHA-256` 校验。

### 4. 本地开发与验证
```bash
pnpm install
pnpm run typecheck
pnpm run knip
pnpm run build
pnpm run preview
```
