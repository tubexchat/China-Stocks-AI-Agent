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

`.xcodeproj` 不入库,改工程配置请改 `project.yml`。签名 / 打包 / 上架脚本(`scripts/release.sh`、`scripts/package-dmg.sh`、`.github/workflows/release.yml`)沿用原项目,产物名为 `AShareAgent-<版本>-<构建号>.dmg`。

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
