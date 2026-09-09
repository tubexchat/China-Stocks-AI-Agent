# A股智能体(AShareAgent for Mac)

> 内部代号 / 模块名沿用 `Axblade`(bundle id `io.primit.axblade` 不变);产品名 **AShareAgent**,显示名「A股智能体」。

原生 macOS **中国 A 股盘面分析工具**。Swift + SwiftUI,**只支持 Apple Silicon(arm64)**,零第三方依赖,无需登录。
盘面数据来自 [同花顺金融数据 API(fuyao)](https://fuyao.aicubes.cn/docs/),全部分析在本地完成;
每个模块都能把本地算好的文字报告一键复制出去。**本项目不含对话 / 聊天功能。**

## 五个盘面模块

| 模块 | 数据 | 本地分析 |
|------|------|---------|
| **涨停情绪市场脉冲** | 涨停池 / 跌停池 / 炸板池 / 连板天梯 | 情绪分(0–100,冰点→亢奋)、封板率、首板/连板/最高板、板位分布、涨停时间分布、封单强度、题材聚类(按 `+` 拆涨停原因)、高度龙头、近 30 日高度 / 连板家数 / 晋级率曲线;可按交易日前后翻页 |
| **龙虎榜资金流拓扑图** | 龙虎榜 `all` + `hot_money` 榜 | 席位(游资 / 机构专用)→ 股票 → 概念 三层资金流图,线宽 ∝ 金额、红买绿卖;点击节点高亮;席位 / 概念净买入排行、最大资金边 |
| **市场热度与飙升雷达** | 热股榜 / 飙升榜(日 / 小时)、个股异动原因 | 螺旋雷达(排名由内向外,点大小 = 热度,红升绿降,圈点 = 共振);热度共振、排名飙升、异动标签统计、异动关键词热度;点击个股看近 30 日热榜排名走势 |
| **本地全市场趋势研究** | 全市场 5000+ 只快照、6 个主要指数 + 320 个行业 / 390 个概念指数日 K | 落 `Application Support/Axblade/research/` 增量缓存(只补新 K 线);市场宽度(涨跌家数、分布、中位数、成交集中度、分板块)、宽度历史、指数 / 板块趋势分(动量 + 均线结构 + 区间位置)、最强 / 最弱板块、近 10 日轮动热力图;个股趋势研究(一年前复权日 K → 趋势 / VaR / 双均线回测 / GBDT / 因子 IC);一键下载整库 Parquet 数据包 |
| **龙虎榜机构与游资观察** | 最近 1 / 3 / 5 / 10 个交易日的龙虎榜 | 机构净买入 / 净卖出、买卖机构数、反复上榜;游资活跃度、净额、偏好概念、逐日操作明细;点击游资 / 股票看详情 |

侧栏或 `⌘1`–`⌘5` 直达模块,`⌘0` 回到模块列表;上次打开的模块下次启动直接恢复。

## 数据源与密钥

- 所有盘面数据:`https://fuyao.aicubes.cn/api/**`,请求头 `X-api-key`。
- 内置一枚默认 Key(`FuyaoKeyStore.builtInKey`);设置 › 数据源 可填自己的 Key,存系统钥匙串(service `io.primit.axblade`,account `fuyao.apikey`),「测试连接」拉一次交易日历验证。
- 限流(业务码 4001 / HTTP 429)、上游超时、5xx 自动退避重试;板块抓取并发 3,单个板块失败沿用缓存。
- 业务错误码按中英文翻译(2001 / 2003 / 3002 / 4001)。

## 环境要求与构建

| 项 | 版本 |
|----|------|
| macOS | 14.0+ |
| 芯片 | Apple Silicon,`ARCHS = arm64` |
| Xcode | 15+ |
| XcodeGen | `brew install xcodegen` |

```bash
xcodegen generate
xcodebuild build -project Axblade.xcodeproj -scheme Axblade -configuration Release -destination 'platform=macOS,arch=arm64'
./scripts/test.sh          # 单元 + 快照测试;SnapshotTests 会把每个模块页渲染成 PNG(路径见 AXBLADE_SNAPSHOT_OUTPUT=…)
```

真实接口冒烟测试(`LiveFuyaoSmokeTests`)默认跳过;在测试宿主容器的 tmp 里创建
`~/Library/Containers/io.primit.axblade/Data/tmp/AXBLADE_LIVE` 文件后再跑即可启用。

`.xcodeproj` 不入库,改工程配置请改 `project.yml`。

## 自动打包与发布(CI)

每次推 `main`,`.github/workflows/release.yml` 在 macOS runner 上:跑测试 → Release 构建 →
`scripts/package-dmg.sh` 打 `AShareAgent-<版本>-<构建号>.dmg`(附 ZIP 与 `latest.json`)→
发布到本仓库的 **GitHub Release**(tag `v<版本>-<构建号>`)→ **同步到 api-dev.pipai.org** →
Lark 群机器人通知(按钮:官网下载 / DMG 直链 / GitHub Release)。

用户在官网 **https://app.pipai.org** 点「Download for Mac」即拿到最新版:落地页请求后端
`GET https://api-dev.pipai.org/v1/releases/latest`(后端仓库 `src/releases.py`),后端优先返回服务器
`RELEASES_DIR`(默认 `/home/ubuntu/releases`)里的最新 `latest.json` 与 `/releases/<文件>` 直链;
服务器上没有时回退到本仓库 GitHub Release 的附件直链,所以即使同步没配好,官网也能下到最新版(只是走 GitHub)。
固定下载链接:`https://api-dev.pipai.org/v1/releases/latest/download`(302 到最新 DMG)。

- 同步需要 secrets `SERVER_HOST` / `SERVER_USERNAME` / `SERVER_SSH_KEY`(与后端仓库同名,可设为组织级);
  缺任一则跳过同步。可选 variables:`RELEASES_DIR`(服务器目录)、`RELEASES_KEEP`(保留最近几个版本,默认 5)。
  同步后会回读线上 `/v1/releases/latest` 校验是否已是本次构建,不一致只告警(通常是后端还没部署 releases 接口)。

- **签名与公证(已配置,线上包为正式签名 + Apple 公证)**:secrets `MAC_SIGNING_P12_BASE64` + `MAC_SIGNING_P12_PASSWORD`
  (Developer ID Application 证书,2031 年 9 月到期)用于签名;`NOTARY_KEY_P8_BASE64` + `NOTARY_KEY_ID` + `NOTARY_ISSUER_ID`
  (App Store Connect API Team Key)用于公证并 staple。打包前工作流会先解码 p8、打印指纹与各字段哈希并调用一次
  `notarytool history` 自检,凭据不对会在「Package DMG」这一步直接失败并给出提示;自检结果随失败日志一起推到 `ci-logs` 分支。
  三项公证 secrets 必须来自同一把 key(Key ID 与 p8 文件名里的 ID 一致)。证书与私钥材料不入库,由账号持有人离线保管。
  若删掉这些 secrets,产物退化为 ad-hoc 签名的测试版:可运行,首次需 **右键 → 打开**。
- Lark webhook 默认写在工作流里,配置 `secrets.LARK_WEBHOOK` 可覆盖。
- CI 失败时日志推到 `ci-logs` 分支(`git fetch origin ci-logs`)。

## 架构

```
Axblade/
├── App/                 AxbladeApp(侧栏 + 模块内容区,⌘0–⌘5)
├── Models/
│   ├── FuyaoModels      fuyao 全部响应形状(snake_case 一一对应,数值字段可选)
│   ├── MarketModels     AgentModule / QuantTool / NumberFormat
│   └── Models           AppSettings(语言、板块口径、回看天数、上次模块)
├── Services/
│   ├── Fuyao/FuyaoClient        X-api-key、信封拆包、错误码、限流重试;AShareSymbol 代码归一化;ShanghaiDate
│   ├── Fuyao/AShareDataService  AShareDataProvider 协议 + FuyaoDataService(全部端点)+ ConcurrentFetch
│   ├── Analytics/LimitUpPulse   涨停情绪分析
│   ├── Analytics/DragonTigerAnalytics  资金流拓扑 FlowGraph + 多日机构 / 游资聚合
│   ├── Analytics/HeatRadar      热榜 × 飙升榜 × 异动交叉
│   ├── Analytics/MarketTrend    市场宽度、TrendMetrics、板块趋势、MarketResearchStore(本地 JSON 缓存)
│   ├── Quant/                   GBDT / 风控 / 因子 / 回测(原生)
│   ├── SettingsStore / KeychainStore / Localization
├── ViewModels/
│   ├── AppViewModel     设置 + 模块选择
│   └── ModuleModels     TradingCalendar + 五个模块的加载 / 状态
└── Views/
    ├── Modules/         ModulesView(路由 + 共用组件)、ChartViews(Swift Charts + 雷达 / 拓扑 Canvas)、五个模块页
    └── Sidebar / Settings(通用、数据源)/ Theme(红涨绿跌)/ BrandMark
```

## 界面主题

深色 / 浅色两套语义 token,数字一律 `.monospacedDigit()`;涨跌遵循 A 股习惯 **红涨绿跌**
(`Theme.up` 红、`Theme.down` 绿;错误 / 成功提示用 `Theme.danger` / `Theme.success`)。

## 数据存放

```
~/Library/Containers/io.primit.axblade/Data/Library/Application Support/Axblade/
├── settings.json          # 语言 / 板块口径 / 回看天数 / 上次模块,不含密钥
└── research/              # 本地全市场研究缓存:series-industry.json / series-cn_concept.json / series-indices.json / snapshot-latest.json / breadth-history.json
```

## 已知边界

不含对话功能;本地研究不解析 Parquet(提供整库下载给 Python / DuckDB 用);多语言之外的语言、多窗口不做。
仅供研究参考,不构成投资建议。
