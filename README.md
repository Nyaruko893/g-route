# G-ROUTE v3 // Google 连通性与路由归属诊断工具

只读网络出口、GeoIP 归属差异与 Google 服务可达性诊断工具。提供无依赖 CLI 探测脚本、本地离线 SVG/PNG 报告导出，以及基于 Cloudflare Workers Static Assets 的静态报告解码与对比页面。

## 核心特性

1. **交互式入口与直通参数**：无参数运行展示单屏交互菜单，支持回车执行标准诊断或先预览请求清单；带参数或非交互管道自动跳过菜单。运行后支持本地导出 SVG（Windows 同步支持原生 PNG）或补充只读查询本地控制接口。
2. **被动网络形态识别**：
   - 默认只读检测出站形态（`本机 TUN · Fake-IP`、`本机 TUN · Real-IP`、`系统代理`、`上游透明路由`、`直连出站`）。
   - 显式传入 `--inspect` / `-Inspect` 时，只读查询本机回环控制接口（`127.0.0.1` 或本地 IPC），按策略链聚合核对 16 个关键域名的路由一致性（仅终端展示，默认不写入 `#r=` 与导出图片）。
3. **多出口路由聚类**：并行探测国内直连参照、默认出站、Google GGC、Cloudflare、OpenAI 与 Anthropic 的出口 IP 与 RTT，按出口槽位自动聚合。
4. **本地离线导出**：跨平台零依赖生成矢量 `.svg`（支持 `--theme light|dark`），Windows 端同步支持内置 `.NET System.Drawing` 导出 2x `.png`，无需打开网页。
5. **低频保护与精准风控检测**：默认仅请求 `searchdomaincheck` 而跳过主动 `/search` 页面爬取（避免触发 Google `/sorry/` 频控，可通过 `--probe-search` / `-ProbeSearch` 显式开启）；统一识别 HTTP 429 `/sorry/`、超时与无 JS 验证页（`enablejs`）。

## 快速开始

### 1. 终端运行（默认进入交互菜单）
- **Cloudflare Workers 短链（推荐）**：
  - Linux / macOS：`bash <(curl -sL https://g-route.429-oops.workers.dev/sh)`
  - Windows PowerShell：`irm https://g-route.429-oops.workers.dev/ps | iex`
- **GitHub Raw 直拉**：
  - Linux / macOS：`bash <(curl -sL https://raw.githubusercontent.com/Nyaruko893/g-route/main/scripts/check.sh)`
  - Windows PowerShell：`irm https://raw.githubusercontent.com/Nyaruko893/g-route/main/scripts/check.ps1 | iex`

### 2. 常用参数
- `--quick` / `-Quick`：跳过交互菜单直接执行标准诊断
- `--inspect` / `-Inspect`（或 `G_ROUTE_INSPECT=1`）：只读查询本机回环控制接口并核对 16 域路由一致性
- `--controller <url|pipe|sock>` / `-Controller`（配 `--secret` / `-Secret`）：指定本机控制接口地址，仅终端展示
- `--svg [path]` / `-Svg [path]`：本地离线生成 SVG 报告（配 `--theme dark` / `--with-rules`）
- `-Png [path]`（Windows）：调用系统 `.NET` 本地导出 2x PNG 报告
- `--probe-search` / `-ProbeSearch`：显式启用主动 Google SERP (`/search`) 探测（默认关闭）
- `--dry-run` / `-DryRun`：仅打印只读请求域名与执行边界后退出，不发起网络请求
- `--ascii` / `--compact` / `NO_COLOR=1`：兼容窄屏或无颜色终端
- `-4` / `-6`（`-V4` / `-V6`）、`-f`（`-Full`）、`-x <proxy>`（`-Proxy`）、`-j`（`-Json`）、`--no-link`（`-NoLink`）

## 安全与隐私边界

1. 不申请管理员 / UAC / `sudo` 权限；
2. 不读取本地配置文件（应用配置、`~/.ssh`、浏览器 Cookie）或枚举进程；
3. 不向服务端上传诊断结果（`#r=`、SVG 与 PNG 均在本地生成，IP 默认脱敏）；
4. 不下载二进制文件；网页端内置实时源码查看与浏览器端 `SHA-256` 校验。

## 本地开发与验证

```bash
pnpm install
pnpm run typecheck
pnpm run knip
pnpm run build
pnpm run preview
```
