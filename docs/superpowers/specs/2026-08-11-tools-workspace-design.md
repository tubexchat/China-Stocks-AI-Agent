# Axblade Tools 工作区(量化工具)— 设计规格

日期:2026-08-11
状态:已定稿(用户选定「原生真算 + AI 解读」)

## 1. 目标

工具栏左上角加 **Home | Tools** 分段切换(参考 GitHub Desktop 风格截图,"Code" 改为 "Tools")。
Tools 下三个原生计算的量化工具,结果可一键发给 AI 解读:

1. **梯度提升树模型**:纯 Swift 小型 GBDT 回归(平方损失、精确分裂),
   用滞后收益/均线比/动量/波动特征预测次日涨跌,输出方向、验证集命中率、特征重要性。
2. **风控模型**:历史 VaR(95/99)、最大回撤、年化波动率、夏普(rf=0)。
3. **历史回测**:双均线交叉策略(默认 5/20,可调)vs 买入持有:总收益/年化/最大回撤/交易次数/胜率 + 净值曲线。

**非目标**:实盘交易、多资产组合、第三方 ML 库(零依赖不变)、GPU/CoreML。

## 2. 数据

`MarketDataService` 增协议方法 `dailyCloses(rawSymbol:days:) -> [Double]`(旧→新),
协议扩展默认实现回落到 `snapshot().closes`;各服务覆写拉长历史:
Binance/MEXC `limit=days`(≤1000)、OKX `limit≤300`、Yahoo 按天数选 `range=1mo/6mo/1y`。
工具默认 365 天(OKX 实际约 300,可用)。

## 3. 量化内核(纯函数,全部 TDD)

- `QuantMath`:`dailyReturns`、`annualizedVolatility`(√252)、`maxDrawdown`、
  `historicalVaR(confidence:)`、`sharpe`。
- `Backtester.run(closes:fast:slow:)` → `BacktestResult { strategyReturn, holdReturn,
  annualized, maxDrawdown, trades, winRate, equityCurve, holdCurve }`;
  规则:快线上穿持仓、下穿空仓,T 日信号 T+1 生效,不计手续费(v1 注明)。
- `GBDT`:回归树(深度默认 3)+ 梯度提升(树数默认 120、学习率 0.1);
  `GBDTForecaster.train(closes:)` → 特征 r1..r5、ma5/ma20-1、mom10、vol10,标签次日收益;
  时间序 80/20 训练/验证;输出 `Forecast { direction, predictedReturn,
  validationHitRate, featureImportance }`。样本 < 60 时报「历史太短」。
- 每个结果类型有 `promptText`(中文数据块)与 `report`(界面展示用行)。

## 4. UI 与流转

- `RootView` 增 `@Published workspace: .home/.tools`(存 AppViewModel,便于「AI 解读」跳转);
  detail 列 toolbar `.navigation` 放分段 Picker(Home=house / Tools=wrench 图标+文字)。
- `ToolsView`:三张工具卡 → 工具页;共用配置表单(数据源 Picker(启用的源)、代码、天数)
  + 工具特参(回测快/慢线;GBDT 树数/深度)→ 运行(loading/错误就地)→ 结果面板
  (指标 + SparkLine 曲线)→「让 AI 解读」。
- 「让 AI 解读」:`AppViewModel.analyze(report:)` = 切回 Home + 新建会话 +
  以「请解读以下量化结果…」+ promptText 作为用户消息直接发送。
- 免责声明一行:结果仅供研究参考,不构成投资建议。

## 5. 测试

QuantMath 手算 fixture;Backtester 构造已知序列验证信号/收益/胜率;
GBDT 拟合 y=x、y=x² 玩具数据(MSE 大幅下降、重要性集中在真特征);
Forecaster 样本不足报错;dailyCloses 各服务 URL/解析(MockHTTP);
analyze() 的会话与 workspace 状态;快照:Tools 首页、回测结果页、GBDT 结果页。
