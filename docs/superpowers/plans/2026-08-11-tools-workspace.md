# Axblade Tools 工作区 — 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 工具栏 Home|Tools 分段切换;Tools 提供原生计算的梯度提升树预测、风控指标、双均线回测,结果一键发给 AI 解读。

**Architecture:** `MarketDataService` 增 `dailyCloses`(协议扩展默认回落);`Quant/` 三个纯函数内核(QuantMath/Backtester/GBDT+Forecaster);`AppViewModel` 增 `workspace` 与 `analyze(report:)`;`ToolsView` 三工具页共用配置表单。

**Tech Stack:** Swift 6.3 / SwiftUI / XCTest。零第三方依赖。

## Global Constraints

- 分支 `feat/tools-workspace`;测试 `./scripts/test.sh`;每任务全绿后 commit。
- UI 中文;颜色只从 `Theme` 取;量化结果附「仅供研究参考,不构成投资建议」。
- closes 一律旧→新;收益按日简单收益;年化 √252。

---

### Task 1: dailyCloses 数据层

**Files:** Modify `MarketDataService.swift`(协议+默认实现)、`CryptoMarketServices.swift`、`YahooFinanceService.swift`;Test 扩 `MarketIntegrationTests.swift`

**Produces:** `func dailyCloses(rawSymbol: String, days: Int) async throws -> [Double]`(旧→新);Binance/MEXC `limit=min(days,1000)`、OKX `limit=min(days,300)`、Yahoo `range: days≤30→1mo, ≤180→6mo, 其余→1y` 后取尾 days。

- [x] 失败测试(MockHTTP:Binance 365 天 URL 带 limit=365;Yahoo 365→range=1y;OKX 截到 300)→ 实现 → 全绿 → Commit `feat: add dailyCloses history fetch`

### Task 2: QuantMath + Backtester(TDD)

**Files:** Create `Axblade/Services/Quant/QuantMath.swift`, `Axblade/Services/Quant/Backtester.swift`;Test `AxbladeTests/QuantMathTests.swift`, `BacktesterTests.swift`

**Produces:**
```swift
enum QuantMath {
    static func dailyReturns(_ closes: [Double]) -> [Double]
    static func annualizedVolatility(returns: [Double]) -> Double
    static func maxDrawdown(_ closes: [Double]) -> Double        // 0.25 = 回撤25%
    static func historicalVaR(returns: [Double], confidence: Double) -> Double  // 正数=损失幅度
    static func sharpe(returns: [Double]) -> Double
}
struct BacktestResult: Equatable { var strategyReturn/holdReturn/annualized/maxDrawdown/winRate: Double; var trades: Int; var equityCurve/holdCurve: [Double]; var fast/slow: Int; var promptText/reportLines }
enum Backtester { static func run(closes: [Double], fast: Int = 5, slow: Int = 20) throws -> BacktestResult }  // closes.count < slow+10 抛 tooShort
struct RiskReport { var var95/var99/maxDrawdown/annualVol/sharpe: Double; var promptText ... }
enum RiskAnalyzer { static func run(closes: [Double]) throws -> RiskReport }
```

- [x] 手算 fixture 失败测试(known 序列的 returns/回撤/VaR 分位、上穿下穿信号与收益)→ 实现 → 全绿 → Commit `feat: add quant math and MA backtester`

### Task 3: GBDT + Forecaster(TDD)

**Files:** Create `Axblade/Services/Quant/GBDT.swift`, `GBDTForecaster.swift`;Test `GBDTTests.swift`

**Produces:**
```swift
struct GBDT {  // 平方损失梯度提升回归
    init(trees: Int = 120, depth: Int = 3, learningRate: Double = 0.1, minSamplesLeaf: Int = 5)
    mutating func fit(features: [[Double]], targets: [Double])
    func predict(_ row: [Double]) -> Double
    var featureImportance: [Double]   // 分裂增益归一化
}
struct Forecast { var predictedReturn: Double; var direction: String; var validationHitRate: Double; var featureImportance: [(String, Double)]; var promptText ... }
enum GBDTForecaster { static func run(closes: [Double], trees: Int, depth: Int) throws -> Forecast }  // 特征 r1..r5, ma5/ma20-1, mom10, vol10;样本<60 抛 tooShort
```

- [x] 失败测试(y=x 线性 MSE 降 90%+;y=x² 非线性可拟合;重要性集中于真特征;样本不足抛错)→ 实现 → 全绿 → Commit `feat: add native GBDT and next-day forecaster`

### Task 4: AppViewModel workspace + analyze(TDD)

**Files:** Modify `AppViewModel.swift`;Test 扩 `AppViewModelTests.swift`

**Produces:** `enum Workspace { case home, tools }`;`@Published var workspace: Workspace = .home`;`func analyze(report: String)` = workspace=.home + newConversation + 发送「请解读以下量化分析结果,指出关键风险与结论:\n\n{report}」。

- [x] 失败测试(analyze 后 workspace==.home、新会话首条用户消息含 report、走 fake service)→ 实现 → 全绿 → Commit `feat: add tools workspace state and AI analyze bridge`

### Task 5: UI

**Files:** Create `Axblade/Views/ToolsView.swift`(工具卡 + 三工具页 + 共用表单/结果面板);Modify `AxbladeApp.swift`(toolbar 分段 Picker + detail 切换)、`SnapshotTests.swift`

- [x] 实现 + 快照(Tools 首页、回测结果、GBDT 结果,用注入的固定 closes 跑真内核渲染)→ 全绿 → Commit `feat: add Tools workspace UI`

### Task 6: 验证收尾

- [x] 真机启动 AX 验证分段切换可达;README 增 Tools 章节;全绿;Commit;合并 main(finishing skill)
