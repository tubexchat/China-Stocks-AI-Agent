import Foundation

// MARK: - 现金流质量稽核台

/// 五个比率全部只用三张报表已提供的字段;分母为 0 或任一侧缺失时留空(nil),不补零。
struct CashFlowMetrics: Equatable, Sendable {
    /// 现金转化率 = 经营现金流净额 / 净利润。
    var cashConversion: Double?
    /// 自由现金流率 = (经营现金流净额 − 购建固定资产等支付的现金) / 营业收入。
    var fcfMargin: Double?
    /// 应计利润率 = (净利润 − 经营现金流净额) / 资产总计。
    var accrualRatio: Double?
    /// 应收压力 = 应收账款 / 营业收入。
    var receivablePressure: Double?
    /// 净现金比例 = (货币资金 − 负债合计) / 资产总计。
    var netCashRatio: Double?

    static func ratio(_ numerator: Double?, _ denominator: Double?) -> Double? {
        guard let numerator, let denominator, denominator != 0 else { return nil }
        return numerator / denominator
    }

    static func difference(_ a: Double?, _ b: Double?) -> Double? {
        guard let a, let b else { return nil }
        return a - b
    }

    static func compute(income: IncomeStatement?, balance: BalanceSheet?, cashFlow: CashFlowStatement?) -> CashFlowMetrics {
        let ocf = cashFlow?.act_cash_flow_net
        return CashFlowMetrics(
            cashConversion: ratio(ocf, income?.net_profit),
            fcfMargin: ratio(difference(ocf, cashFlow?.pay_fixed_assets_etc_cash), income?.operating_income),
            accrualRatio: ratio(difference(income?.net_profit, ocf), balance?.assets_total),
            receivablePressure: ratio(balance?.accounts_receivable, income?.operating_income),
            netCashRatio: ratio(difference(balance?.cash, balance?.total_debt), balance?.assets_total)
        )
    }
}

struct CashFlowAuditReport: Equatable, Sendable {
    /// 一个报告期(三张表按 `period_end_ms` 对齐)。
    struct Period: Equatable, Sendable, Identifiable {
        var periodEndMs: Int64
        var label: String
        /// 三张表里最晚的披露日。
        var reportDateMs: Int64?
        var income: IncomeStatement?
        var balance: BalanceSheet?
        var cashFlow: CashFlowStatement?
        var metrics: CashFlowMetrics

        var id: Int64 { periodEndMs }
        var netProfit: Double? { income?.net_profit }
        var revenue: Double? { income?.operating_income }
        var ocf: Double? { cashFlow?.act_cash_flow_net }
        var capex: Double? { cashFlow?.pay_fixed_assets_etc_cash }
        var fcf: Double? { CashFlowMetrics.difference(ocf, capex) }
        /// 应计项 = 净利润 − 经营现金流(利润—经营现金流桥的中间项)。
        var accruals: Double? { CashFlowMetrics.difference(netProfit, ocf) }
        var reportDate: Date? { reportDateMs.map { Date(timeIntervalSince1970: Double($0) / 1000) } }
    }

    struct Company: Equatable, Sendable, Identifiable {
        var thscode: String
        var name: String
        /// 升序,最多 5 期,已按披露时点过滤。
        var periods: [Period]
        /// 取数失败时的错误文案;此时 periods 为空。
        var error: String?
        var id: String { thscode }

        var latest: Period? { periods.last }
        /// 5 年现金转化率均值(只算有值的年份)。
        var averageCashConversion: Double? {
            let values = periods.compactMap(\.metrics.cashConversion)
            return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
        /// 经营现金流 ≥ 净利润的年份数 / 两者都有值的年份数。
        var yearsCashCovered: Int { periods.filter { ($0.ocf ?? -.infinity) >= ($0.netProfit ?? .infinity) }.count }
        var yearsComparable: Int { periods.filter { $0.ocf != nil && $0.netProfit != nil }.count }
        /// 5 年自由现金流合计(任一年缺失则为 nil)。
        var fcfTotal: Double? {
            let values = periods.map(\.fcf)
            guard !values.isEmpty, values.allSatisfy({ $0 != nil }) else { return nil }
            return values.compactMap { $0 }.reduce(0, +)
        }
        /// 所用 8 个字段在各期的缺失个数。
        var missingFields: Int { periods.reduce(0) { $0 + CashFlowAuditAnalyzer.missingCount(in: $1) } }
        var expectedFields: Int { periods.count * CashFlowAuditAnalyzer.usedFields.count }
    }

    /// 字段完整度审计:一个字段在全部「公司 × 期」里出现了多少次。
    struct FieldCompleteness: Equatable, Sendable, Identifiable {
        var field: String
        var statement: String
        var present: Int
        var expected: Int
        var id: String { field }
        var ratio: Double { expected == 0 ? 0 : Double(present) / Double(expected) }
    }

    var generatedAt: Date
    /// 披露时点:只保留 `report_date_ms` 不晚于此日的报告期。
    var asOf: Date
    var companies: [Company]
    var fields: [FieldCompleteness]

    var loaded: [Company] { companies.filter { $0.error == nil && !$0.periods.isEmpty } }
    var failed: [Company] { companies.filter { $0.error != nil } }
    /// 最新报告期的日期范围(不同公司可能不同)。
    var latestPeriodLabels: [String] { Array(Set(loaded.compactMap { $0.latest?.label })).sorted() }
    var totalPeriods: Int { loaded.reduce(0) { $0 + $1.periods.count } }
    var overallCompleteness: Double {
        let expected = fields.reduce(0) { $0 + $1.expected }
        return expected == 0 ? 0 : Double(fields.reduce(0) { $0 + $1.present }) / Double(expected)
    }

    func sorted(by key: CashFlowAuditSortKey) -> [Company] {
        loaded.sorted { a, b in
            let x = key.value(a), y = key.value(b)
            switch (x, y) {
            case let (x?, y?): return key.ascending ? x < y : x > y
            case (nil, _?): return false
            case (_?, nil): return true
            default: return a.name < b.name
            }
        } + failed
    }

    var promptText: String {
        let pct: (Double?) -> String = { $0.map { RiskReport.percent($0) } ?? "—" }
        let num: (Double?) -> String = { $0.map { NumberFormat.number($0) } ?? "—" }
        let rows = sorted(by: .cashConversion).filter { $0.error == nil }.map { company -> String in
            let m = company.latest?.metrics
            return "\(company.name)(\(company.latest?.label ?? "—")):现金转化 \(num(m?.cashConversion)),FCF率 \(pct(m?.fcfMargin)),应计率 \(pct(m?.accrualRatio)),应收压力 \(pct(m?.receivablePressure)),净现金比例 \(pct(m?.netCashRatio));5年均值 \(num(company.averageCashConversion)),现金覆盖利润 \(company.yearsCashCovered)/\(company.yearsComparable) 年"
        }
        let fieldText = fields.map { "\($0.field) \($0.present)/\($0.expected)" }.joined(separator: ",")
        let failures = failed.map { "\($0.thscode) \($0.error ?? "")" }.joined(separator: ";")
        return """
        【现金流质量稽核台 · 观察池 \(companies.count) 只 · 年报 ×5 · 披露截止 \(ShanghaiDate.dayFormatter.string(from: asOf)) · 生成 \(ShanghaiDate.dayFormatter.string(from: generatedAt))】
        \(rows.joined(separator: "\n"))
        字段完整度:\(fieldText);整体 \(RiskReport.percent(overallCompleteness))
        \(failures.isEmpty ? "" : "取数失败:\(failures)\n")口径:现金转化率=经营现金流净额/净利润;自由现金流率=(经营现金流净额−购建固定资产等支付现金)/营业收入;应计利润率=(净利润−经营现金流净额)/资产总计;应收压力=应收账款/营业收入;净现金比例=(货币资金−负债合计)/资产总计;分母为 0 或缺失留空。仅供研究参考,不构成投资建议。
        """
    }
}

enum CashFlowAuditSortKey: String, CaseIterable, Identifiable, Sendable {
    case cashConversion, fcfMargin, accrualRatio, receivablePressure, netCashRatio, averageCashConversion
    var id: String { rawValue }

    /// 应计率、应收压力越低越好,升序排。
    var ascending: Bool { self == .accrualRatio || self == .receivablePressure }

    func value(_ company: CashFlowAuditReport.Company) -> Double? {
        switch self {
        case .cashConversion: company.latest?.metrics.cashConversion
        case .fcfMargin: company.latest?.metrics.fcfMargin
        case .accrualRatio: company.latest?.metrics.accrualRatio
        case .receivablePressure: company.latest?.metrics.receivablePressure
        case .netCashRatio: company.latest?.metrics.netCashRatio
        case .averageCashConversion: company.averageCashConversion
        }
    }
}

enum CashFlowAuditAnalyzer {
    /// 每只股票的原始三表(年报,最多 5 期)。
    struct Input: Sendable {
        var thscode: String
        var name: String
        var income: [IncomeStatement] = []
        var balance: [BalanceSheet] = []
        var cashFlow: [CashFlowStatement] = []
        var error: String?
    }

    /// 计算用到的 8 个字段(字段名, 所属报表)。
    static let usedFields: [(field: String, statement: String)] = [
        ("net_profit", "income"), ("operating_income", "income"),
        ("act_cash_flow_net", "cashflow"), ("pay_fixed_assets_etc_cash", "cashflow"),
        ("assets_total", "balance"), ("accounts_receivable", "balance"), ("cash", "balance"), ("total_debt", "balance")
    ]

    static func fieldValues(in period: CashFlowAuditReport.Period) -> [String: Double?] {
        [
            "net_profit": period.income?.net_profit,
            "operating_income": period.income?.operating_income,
            "act_cash_flow_net": period.cashFlow?.act_cash_flow_net,
            "pay_fixed_assets_etc_cash": period.cashFlow?.pay_fixed_assets_etc_cash,
            "assets_total": period.balance?.assets_total,
            "accounts_receivable": period.balance?.accounts_receivable,
            "cash": period.balance?.cash,
            "total_debt": period.balance?.total_debt
        ]
    }

    static func missingCount(in period: CashFlowAuditReport.Period) -> Int {
        let values = fieldValues(in: period)
        return usedFields.filter { values[$0.field].flatMap { $0 } == nil }.count
    }

    /// 三张表按 `period_end_ms` 对齐;只保留披露日不晚于 `asOf` 的期(缺披露日按可用处理);升序,最多 `keep` 期。
    static func alignPeriods(
        income: [IncomeStatement], balance: [BalanceSheet], cashFlow: [CashFlowStatement],
        asOf: Date, keep: Int = 5
    ) -> [CashFlowAuditReport.Period] {
        let asOfMs = Int64(asOf.timeIntervalSince1970 * 1000)
        let incomeByEnd = Dictionary(income.map { ($0.period_end_ms, $0) }, uniquingKeysWith: { a, _ in a })
        let balanceByEnd = Dictionary(balance.map { ($0.period_end_ms, $0) }, uniquingKeysWith: { a, _ in a })
        let cashByEnd = Dictionary(cashFlow.map { ($0.period_end_ms, $0) }, uniquingKeysWith: { a, _ in a })
        var keySet = Set<Int64>(incomeByEnd.keys)
        keySet.formUnion(balanceByEnd.keys)
        keySet.formUnion(cashByEnd.keys)
        let keys: [Int64] = keySet.sorted()
        let periods: [CashFlowAuditReport.Period] = keys.compactMap { (end: Int64) -> CashFlowAuditReport.Period? in
            let i: IncomeStatement? = incomeByEnd[end]
            let b: BalanceSheet? = balanceByEnd[end]
            let c: CashFlowStatement? = cashByEnd[end]
            let reportDates: [Int64] = [i?.report_date_ms, b?.report_date_ms, c?.report_date_ms].compactMap { $0 }
            // 披露时点控制:任一张表的披露日晚于 asOf,这一期就还「不该被看到」。
            if let latestReport = reportDates.max(), latestReport > asOfMs { return nil }
            let fallback: String = ShanghaiDate.string(Date(timeIntervalSince1970: Double(end) / 1000))
            let label: String = i?.periodLabel ?? c?.periodLabel ?? b?.periodLabel ?? fallback
            return CashFlowAuditReport.Period(
                periodEndMs: end, label: label, reportDateMs: reportDates.max(),
                income: i, balance: b, cashFlow: c,
                metrics: CashFlowMetrics.compute(income: i, balance: b, cashFlow: c)
            )
        }
        return Array(periods.suffix(keep))
    }

    static func run(generatedAt: Date = Date(), asOf: Date, inputs: [Input]) -> CashFlowAuditReport {
        let companies: [CashFlowAuditReport.Company] = inputs.map { input in
            if let error = input.error {
                return .init(thscode: input.thscode, name: input.name, periods: [], error: error)
            }
            let periods = alignPeriods(income: input.income, balance: input.balance, cashFlow: input.cashFlow, asOf: asOf)
            return .init(thscode: input.thscode, name: input.name, periods: periods, error: nil)
        }
        let allPeriods = companies.flatMap(\.periods)
        let fields = usedFields.map { entry -> CashFlowAuditReport.FieldCompleteness in
            let present = allPeriods.filter { fieldValues(in: $0)[entry.field].flatMap { $0 } != nil }.count
            return .init(field: entry.field, statement: entry.statement, present: present, expected: allPeriods.count)
        }
        return CashFlowAuditReport(generatedAt: generatedAt, asOf: asOf, companies: companies, fields: fields)
    }
}
