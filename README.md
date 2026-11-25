# G-ROUTE // Google 生态送中与分流体检仪

> 对标“Google 专属、反焦虑版 IPQuality”：以 **零依赖 CLI 为真值探针引擎**，以 **Cloudflare Workers Static Assets 网页为精工仪器体检卡与排错台**，通过本地离线 `#r=` 压缩编码实现**永久 $0 成本、服务端零落库、零隐私上传**的闭环体验。

## 快速开始

### 1. 一行命令体检
- **从 GitHub Raw 直接运行（Linux / macOS / VPS）**：
  ```bash
  bash <(curl -sL https://raw.githubusercontent.com/Nyaruko893/g-route/main/scripts/check.sh)
  ```
- **部署到 Cloudflare Workers 后的短链**：
  - Linux / macOS / VPS：
    ```bash
    bash <(curl -sL https://<your-worker>.workers.dev/sh)
    ```
  - Windows PowerShell (5.1 & 7)：
    ```powershell
    irm https://<your-worker>.workers.dev/ps | iex
    ```
- **高敏感审阅模式（先下载看源码，再运行）**：
  ```bash
  curl -sL https://raw.githubusercontent.com/Nyaruko893/g-route/main/scripts/check.sh -o g-route.sh && less g-route.sh && bash g-route.sh
  ```
  ```powershell
  iwr https://raw.githubusercontent.com/Nyaruko893/g-route/main/scripts/check.ps1 -OutFile g-route.ps1; notepad g-route.ps1; .\g-route.ps1
  ```

### 2. 参数与安全审计选项
- `--dry-run` / `-DryRun`：零发包安全审计模式，打印全部只读请求域名与权限边界后立即退出
- `--controller <url>` / `-Controller <url>`（配 `--secret` / `-Secret` 或环境变量 `G_ROUTE_CONTROLLER` / `G_ROUTE_SECRET`）：可选显式接入本地 Clash/Mihomo 控制 API，支持 HTTP（`http://127.0.0.1:9090`）、Windows 命名管道（如 Clash Verge Rev 的 `\\.\pipe\verge-mihomo` / Mihomo Party 的 `\\.\pipe\mihomo-party`）及 Unix Socket（`/tmp/verge/verge-mihomo.sock`）；**仅在本屏终端**只读展示各探测域名的命中规则与策略链，节点名绝不写入 `#r=` 分享链接
- `-4` / `-6`（`-V4` / `-V6`）：单栈探测
- `-f`（`-Full`）：显示完整 IP（默认自动脱敏如 `38.59.*.*`）
- `-x <proxy>`（`-Proxy <proxy>`）：显式指定 HTTP/SOCKS5 代理（Windows 自动读取系统代理与 TUN Fake-IP）
- `-j`（`-Json`）：输出紧凑结构化 JSON (`CliReportV1`)
- `--no-link`（`-NoLink`）：不输出底部离线 `#r=` 链接

### 3. 权限边界契约（4 个绝不）
1. 绝不申请管理员 / UAC / `sudo` 提权；
2. 绝不读取磁盘配置文件（`~/.ssh`、`%APPDATA%` 代理订阅、浏览器 Cookie）；
3. 绝不向任何服务器上传检测结果（`#r=` 链接 100% 本地离线压缩编码，默认 IP 脱敏）；
4. 绝不下载二进制文件或执行混淆密文；网页启动台内置实时源码审阅器与浏览器端 `SHA-256` 校验。

### 4. 本地验证与可选配置
```bash
pnpm install
pnpm run typecheck
pnpm run knip
pnpm run build
pnpm run preview
```

如需在网页启动台展示开源溯源链接，可在 `wrangler.jsonc` `vars` 或 Cloudflare 环境变量中设置 `GITHUB_REPO_URL=https://github.com/<owner>/<repo>`。
