import Foundation

// MARK: - 单股财务体检

/// 最近 8 期季度报表(三表按 `period_end_ms` 对齐)+ 最新报告期财务指标。
/// 利润表 / 现金流量表的季度值是**年初至今累计**;单季值只在同一财年上一期也在数据里时才推算,否则留空。
struct FinancialHealthReport: Equatable, Sendable {
    struct Period: Equatable, Sendable, Identifiable {
        var periodEndMs: Int64
        var label: String
        var fiscalYear: Int?
        var quarter: Int?
        var reportDateMs: Int64?
        var income: IncomeStatement?
        var balance: BalanceSheet?
        var cashFlow: CashFlowStatement?

        // 累计值(报表原值)
        var revenue: Double?
        var netProfit: Double?
        var parentNetProfit: Double?
        var operatingProfit: Double?
        var ocf: Double?
        var capex: Double?
        var rdExpenses: Double?
        var eps: Double?
        // 单季推算值
        var revenueQ: Double?
        var netProfitQ: Double?
        var ocfQ: Double?
        // 同比(与上一财年同一报告期比,累计口径)
        var revenueYoY: Double?
        var netProfitYoY: Double?
        var ocfYoY: Double?

        var id: Int64 { periodEndMs }
        var fcf: Double? { CashFlowMetrics.difference(ocf, capex) }
        var grossMargin: Double? { CashFlowMetrics.ratio(CashFlowMetrics.difference(revenue, income?.operating_costs), revenue) }
        var netMargin: Double? { CashFlowMetrics.ratio(netProfit, revenue) }
        var cashConversion: Double? { CashFlowMetrics.ratio(ocf, netProfit) }
        var assets: Double? { balance?.assets_total }
        var debt: Double? { balance?.total_debt }
        var cash: Double? { balance?.cash }
        var equity: Double? { balance?.holder_equity_total }
        var receivables: Double? { balance?.accounts_receivable }
        var debtRatio: Double? { CashFlowMetrics.ratio(debt, assets) }
        var cashToDebt: Double? { CashFlowMetrics.ratio(cash, debt) }
        var currentAssetRatio: Double? { CashFlowMetrics.ratio(balance?.total_current_assets, assets) }
        var receivableToRevenue: Double? { CashFlowMetrics.ratio(receivables, revenue) }
        var reportDate: Date? { reportDateMs.map { Date(timeIntervalSince1970: Double($0) / 1000) } }
        var periodEnd: Date { Date(timeIntervalSince1970: Double(periodEndMs) / 1000) }
        /// 三张表是否齐全。
        var isComplete: Bool { income != nil && balance != nil && cashFlow != nil }
    }

    var thscode: String
    var name: String
    var currency: String
    var generatedAt: Date
    /// 升序,最多 8 期。
    var periods: [Period]
    var indicators: FinancialIndicatorsData?
    /// 指标对应的报告期参数(`2026-2`)。
    var indicatorReport: String?

    var latest: Period? { periods.last }
    var previous: Period? { periods.count >= 2 ? periods[periods.count - 2] : nil }
    /// 上一财年同一报告期。
    var yearAgo: Period? {
        guard let latest, let year = latest.fiscalYear, let quarter = latest.quarter else { return nil }
        return periods.first { $0.fiscalYear == year - 1 && $0.quarter == quarter }
    }
    var completePeriods: Int { periods.filter(\.isComplete).count }

    var promptText: String {
        let pct: (Double?) -> String = { $0.map { RiskReport.percent($0) } ?? "—" }
        let yuan: (Double?) -> String = { $0.map(MoneyFormat.yuan) ?? "—" }
        guard let latest else { return "【单股财务体检 · \(name) \(thscode)】没有拿到报表数据" }
        var lines = ["【单股财务体检 · \(name) \(thscode) · 最新报告期 \(latest.label)(累计)· 币种 \(currency) · 生成 \(ShanghaiDate.dayFormatter.string(from: generatedAt))】"]
        lines.append("增长:营业收入 \(yuan(latest.revenue)),同比 \(pct(latest.revenueYoY));净利润 \(yuan(latest.netProfit)),同比 \(pct(latest.netProfitYoY));经营现金流净额 \(yuan(latest.ocf)),同比 \(pct(latest.ocfYoY))")
        lines.append("盈利:毛利率 \(pct(latest.grossMargin)),净利率 \(pct(latest.netMargin)),归母净利润 \(yuan(latest.parentNetProfit)),基本 EPS \(latest.eps.map { NumberFormat.number($0) } ?? "—") 元")
        lines.append("现金流:经营现金流 / 净利润 \(latest.cashConversion.map { NumberFormat.number($0) } ?? "—"),购建固定资产等支付 \(yuan(latest.capex)),自由现金流 \(yuan(latest.fcf))")
        lines.append("杠杆:资产负债率 \(pct(latest.debtRatio)),货币资金 / 负债合计 \(latest.cashToDebt.map { NumberFormat.number($0) } ?? "—"),资产总计 \(yuan(latest.assets)),股东权益 \(yuan(latest.equity))")
        if let q = latest.revenueQ ?? latest.netProfitQ {
            _ = q
            lines.append("单季推算(本期累计 − 同财年上期累计):营收 \(yuan(latest.revenueQ)),净利润 \(yuan(latest.netProfitQ)),经营现金流 \(yuan(latest.ocfQ))")
        }
        let series = periods.map { "\($0.label) 营收\(yuan($0.revenue)) 净利\(yuan($0.netProfit)) 经营现金流\(yuan($0.ocf))" }.joined(separator: ";")
        lines.append("8 期序列(累计):\(series)")
        if let indicators, !indicators.isEmpty {
            let text = indicators.abilities.map { ability in
                "\(FinancialIndicatorCatalog.abilityName(ability.ability)):" + ability.indicators.map { "\(FinancialIndicatorCatalog.name($0.index_id)) \($0.value ?? "—")" }.joined(separator: " ")
            }.joined(separator: ";")
            lines.append("财务指标(\(indicatorReport ?? "")):\(text)")
        }
        lines.append("说明:季度利润表 / 现金流量表为年初至今累计值,资产负债表为期末时点值;null 保持缺失不补零;未计算估值、行业均值与评分。仅供研究参考,不构成投资建议。")
        return lines.joined(separator: "\n")
    }
}

enum FinancialHealthAnalyzer {
    /// 同比 = (本期 − 上年同期) / |上年同期|;上年同期缺失或为 0 留空。
    static func yoy(current: Double?, previous: Double?) -> Double? {
        guard let current, let previous, previous != 0 else { return nil }
        return (current - previous) / abs(previous)
    }

    /// 单季值:Q1 = 累计;Qn = 本期累计 − 同财年 Q(n−1) 累计;上一期不在数据里则留空。
    static func singleQuarter(current: Double?, previousCumulative: Double?, quarter: Int?) -> Double? {
        guard let quarter else { return nil }
        if quarter == 1 { return current }
        guard let current, let previousCumulative else { return nil }
        return current - previousCumulative
    }

    static func run(
        thscode: String, name: String, generatedAt: Date = Date(),
        income: [IncomeStatement], balance: [BalanceSheet], cashFlow: [CashFlowStatement],
        indicators: FinancialIndicatorsData?, indicatorReport: String?, keep: Int = 8
    ) -> FinancialHealthReport {
        let incomeByEnd = Dictionary(income.map { ($0.period_end_ms, $0) }, uniquingKeysWith: { a, _ in a })
        let balanceByEnd = Dictionary(balance.map { ($0.period_end_ms, $0) }, uniquingKeysWith: { a, _ in a })
        let cashByEnd = Dictionary(cashFlow.map { ($0.period_end_ms, $0) }, uniquingKeysWith: { a, _ in a })
        // 分步写明类型:链式 Set/union/sorted/suffix 会让 CI 上的编译器类型推断超时。
        var keySet = Set<Int64>(incomeByEnd.keys)
        keySet.formUnion(balanceByEnd.keys)
        keySet.formUnion(cashByEnd.keys)
        let sortedKeys: [Int64] = keySet.sorted()
        let keys: [Int64] = Array(sortedKeys.suffix(keep))

        var periods: [FinancialHealthReport.Period] = keys.map { (end: Int64) -> FinancialHealthReport.Period in
            let i: IncomeStatement? = incomeByEnd[end]
            let b: BalanceSheet? = balanceByEnd[end]
            let c: CashFlowStatement? = cashByEnd[end]
            let meta: (any FinancialStatement)? = i ?? c ?? b
            let reportDates: [Int64] = [i?.report_date_ms, b?.report_date_ms, c?.report_date_ms].compactMap { $0 }
            return FinancialHealthReport.Period(
                periodEndMs: end,
                label: meta?.periodLabel ?? ShanghaiDate.string(Date(timeIntervalSince1970: Double(end) / 1000)),
                fiscalYear: meta?.fiscal_year, quarter: meta?.quarterIndex,
                reportDateMs: reportDates.max(),
                income: i, balance: b, cashFlow: c,
                revenue: i?.operating_income, netProfit: i?.net_profit, parentNetProfit: i?.parent_holder_net_profit,
                operatingProfit: i?.operating_profit, ocf: c?.act_cash_flow_net, capex: c?.pay_fixed_assets_etc_cash,
                rdExpenses: i?.research_and_development_expenses, eps: i?.basic_eps
            )
        }

        func find(year: Int?, quarter: Int?) -> FinancialHealthReport.Period? {
            guard let year, let quarter else { return nil }
            return periods.first { $0.fiscalYear == year && $0.quarter == quarter }
        }
        for index in periods.indices {
            let p = periods[index]
            let prior = find(year: p.fiscalYear, quarter: p.quarter.map { $0 - 1 })
            periods[index].revenueQ = singleQuarter(current: p.revenue, previousCumulative: prior?.revenue, quarter: p.quarter)
            periods[index].netProfitQ = singleQuarter(current: p.netProfit, previousCumulative: prior?.netProfit, quarter: p.quarter)
            periods[index].ocfQ = singleQuarter(current: p.ocf, previousCumulative: prior?.ocf, quarter: p.quarter)
            let yearAgo = find(year: p.fiscalYear.map { $0 - 1 }, quarter: p.quarter)
            periods[index].revenueYoY = yoy(current: p.revenue, previous: yearAgo?.revenue)
            periods[index].netProfitYoY = yoy(current: p.netProfit, previous: yearAgo?.netProfit)
            periods[index].ocfYoY = yoy(current: p.ocf, previous: yearAgo?.ocf)
        }

        let currency = income.first?.currency ?? balance.first?.currency ?? cashFlow.first?.currency ?? "CNY"
        return FinancialHealthReport(
            thscode: thscode, name: name, currency: currency, generatedAt: generatedAt,
            periods: periods, indicators: indicators, indicatorReport: indicatorReport
        )
    }
}

/// 财务指标 `index_id` → 中文名 / 单位(只做展示映射,不做任何评分)。
enum FinancialIndicatorCatalog {
    static let names: [String: String] = [
        "total_assets_growth_ratio": "总资产增长率",
        "net_profit_yoy_growth_ratio": "净利润同比增长率",
        "operating_income_yoy_growth_ratio": "营业收入同比增长率",
        "operating_profit_yoy_growth_ratio": "营业利润同比增长率",
        "calculate_operating_income_yoy_growth_ratio": "营业收入同比增长率",
        "calculate_operating_profit_yoy_growth_ratio": "营业利润同比增长率",
        "calculate_parent_holder_net_profit_yoy_growth_ratio": "归母净利润同比增长率",
        "fixed_asset_invest_expansion_ratio": "固定资产投资扩张率",
        "sale_gross_margin": "销售毛利率",
        "sale_net_interest_ratio": "销售净利率",
        "total_assets_net_ratio": "总资产收益率",
        "index_deduct_weighted_avg_roe": "扣非加权净资产收益率",
        "index_weighted_avg_roe": "加权净资产收益率",
        "current_ratio": "流动比率",
        "quick_ratio": "速动比率",
        "assets_debt_ratio": "资产负债率",
        "cash_ratio": "现金比率",
        "earned_interest_multiple": "已获利息倍数",
        "long_term_debt_equity_ratio": "长期负债权益比率",
        "total_assets_turnover_ratio": "总资产周转率",
        "inventory_turnover_ratio": "存货周转率",
        "current_assets_turnover_ratio": "流动资产周转率",
        "receive_account_turnover_ratio": "应收账款周转率",
        "cash_operating_index": "现金营运指数",
        "operating_cash_flow_net_divide_income": "销售现金比率",
        "net_profit_cash_content": "净利润现金含量",
        "operating_cash_net_yoy_growth_ratio": "现金流量净额增长率",
        "cash_meet_invest_ratio": "现金满足投资比率"
    ]

    static let abilities: [String: String] = [
        "growth": "成长能力", "profitability": "盈利能力", "solvency": "偿债能力", "operation": "营运能力", "cash-flow": "现金流"
    ]

    static func name(_ indexID: String) -> String { names[indexID] ?? indexID }
    static func abilityName(_ ability: String) -> String { abilities[ability] ?? ability }

    /// 名称含增长率 / 毛利率 / 净利率 / 收益率 / 资产负债率 / 现金比率 / 现金含量 / 现金比率 的按百分数展示。
    static func isPercent(_ indexID: String) -> Bool {
        let name = name(indexID)
        return ["增长率", "毛利率", "净利率", "收益率", "资产负债率", "现金比率", "现金含量", "现金比率", "扩张率"].contains { name.contains($0) }
    }

    /// 上游原始字符串 → 展示文本(百分数保留 2 位,其余去尾零)。
    static func display(_ indicator: FinancialIndicator) -> String {
        guard let value = indicator.doubleValue else { return "—" }
        if isPercent(indicator.index_id) { return NumberFormat.number(value) + "%" }
        return NumberFormat.number(value)
    }
}
