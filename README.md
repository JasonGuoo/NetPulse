# WiFi Doctor

一款 macOS 原生的 **WiFi / 网络健康诊断应用**，霓虹 HUD 风格界面，回答一个核心问题：
**"我的网络现在怎么样？网页慢到底是慢在哪？"**

**多语言**：中文 / English / 日本語 / 한국어，顶栏地球图标随时切换（或跟随系统）；诊断输入框回车即测并自动记住最近测试过的地址；顶栏"刷新"按钮一键重采全部数据（含周边 WiFi 扫描）。

## 功能

| 页面 | 内容 |
|---|---|
| **概况** | 网关、DNS（含来源：DHCP/手动）、代理、VPN、公网出口 IP 与归属（运营商/城市/边缘节点）、WiFi 信号速览、丢包延迟、健康结论 |
| **连接** | 所有软件（浏览器/IM/后台服务等）的网络连接：远端地址、实时 ↓↑ 速率、累计流量、按进程聚合排行、本机监听端口 |
| **链路** | WiFi 射频细节：RSSI/噪声/SNR/协商速率/信道宽度/MCS/PHY、信号历史走势、2.4G/5G 信道占用频谱 + 雷达图、网关与公网 ping 走势 |
| **速率** | Cloudflare 实测下载吞吐表盘 vs WiFi 协商速率 vs 全机实时流量对照 |
| **诊断** | 输入网址 → 五段耗时分解（DNS/TCP/TLS/首字节/下载）+ DNS 对比 → 自动归因"慢在哪"并给建议 |

健康结论自动判定：WiFi 链路差（信号弱/同频干扰）、运营商问题、DNS 慢建议换 1.1.1.1、服务器响应慢（TTFB）、带宽瓶颈等。

## 构建与打包

需要一次性的 Xcode Command Line Tools（仅构建机需要，**最终用户零依赖**）：

```bash
swift build                 # 调试构建
swift test                  # 运行 18 个解析器/诊断单测
./scripts/make-app.sh       # 产出 build/WiFiDoctor.app（零依赖、可直接分发）
```

`WiFiDoctor.app` 为原生二进制 + 系统 framework，无 Python/Swift 运行时依赖，拷贝即用。
首次打开若提示无法验证开发者：右键 App → 打开。

## 技术口径

- **数据源（全部免 sudo、免定位权限）**：CoreWLAN（RSSI/噪声/协商速率/信道）、`system_profiler SPAirPortDataType -json`（SSID/信道宽度/MCS/周边网络扫描）、`lsof -F`（连接清单）、`nettop`（字节计数差分出速率）、`route`/`scutil`/`ipconfig`（网关/DNS/代理/VPN）、`ping`（丢包延迟）、URLSession TaskMetrics（五段耗时）、Cloudflare `__down`（吞吐）
- **SSID 隐私**：macOS Sonoma 起 SSID 属定位敏感信息——本应用通过 `system_profiler` 读取当前连接的 SSID（实测可用）；若未来系统收紧导致读不到，界面会显示"受系统隐私保护"而不影响其他指标
- **逐连接丢包**：无 root 无法抓包统计单条连接的丢包，以「对远端 ping 丢包 + 系统 TCP 重传统计（`netstat -s`）」近似，并在 UI 标注
- **诊断规则**：网关丢包 >2%/延迟 >30ms 且 RSSI < -70 → WiFi 链路差；网关好但公网差 → 运营商；DNS >200ms 且公共 DNS <50ms → 换 DNS；TTFB 高 → 服务器慢；延迟正常吞吐低 → 带宽瓶颈

## 目录结构

```
wifi-doctor/
├── Package.swift
├── scripts/make-app.sh        # 打包 .app
├── Sources/WiFiDoctor/
│   ├── App.swift              # 入口/窗口/图标/自检（--probe --selftest-png --make-icon 为开发用）
│   ├── Theme.swift            # 霓虹 HUD 设计令牌
│   ├── AppModel.swift         # 全局状态中枢
│   ├── Components/            # NeonCard / HealthRing / Sparkline / 频谱 / 雷达 / 表盘
│   ├── Views/                 # 五个页面
│   └── Core/                  # 采集与诊断子系统
└── Tests/WiFiDoctorTests/     # 解析器单测（样本来自实机输出）
```

## 已知限制

- 免 sudo 下其他用户/root 进程的连接不显示 PID（正常现象）
- 常驻采样开销很轻：lsof/nettop 每 2 秒各一次（约几十 ms CPU），ping 每目标 1 次/秒，测速仅手动触发（约消耗 100 MB 流量）
- 公网 IP 查询（Cloudflare trace + ipinfo）每 5 分钟一次，弱网时不阻塞界面
