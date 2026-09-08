import Foundation

/// 市场热度与飙升雷达:热股榜 × 飙升榜 × 个股异动原因 的交叉分析。
struct HeatRadarReport: Equatable, Sendable {
    struct RadarPoint: Equatable, Sendable, Identifiable {
        var thscode: String
        var name: String
        /// 热股榜排名(1 = 最热);不在热股榜为 nil。
        var hotRank: Int?
        /// 飙升榜排名;不在飙升榜为 nil。
        var surgeRank: Int?
        var heat: Double
        var rankChange: Int?
        var trend: String
        /// 同时在热股榜与飙升榜。
        var resonance: Bool
        var anomalyTag: String?
        var keywords: [String]
        var id: String { thscode }
    }

    struct KeywordHeat: Equatable, Sendable, Identifiable {
        var keyword: String
        var count: Int
        var stocks: [String]
        var id: String { keyword }
    }

    struct TagCount: Equatable, Sendable, Identifiable {
        var tag: String
        var count: Int
        var id: String { tag }
    }

    var period: HotListPeriod
    var points: [RadarPoint]
    var resonance: [RadarPoint]
    var climbers: [RadarPoint]
    var keywords: [KeywordHeat]
    var tags: [TagCount]
    var anomalies: [AnomalyItem]
    var fetchedAt: Date

    var promptText: String {
        let hot = points.filter { $0.hotRank != nil }.sorted { ($0.hotRank ?? 99) < ($1.hotRank ?? 99) }.prefix(15)
            .map { "\($0.hotRank ?? 0).\($0.name)\($0.rankChange.map { $0 > 0 ? "↑\($0)" : ($0 < 0 ? "↓\(-$0)" : "") } ?? "")\($0.anomalyTag.map { "[\($0)]" } ?? "")" }
            .joined(separator: " ")
        let surge = points.filter { $0.surgeRank != nil }.sorted { ($0.surgeRank ?? 99) < ($1.surgeRank ?? 99) }.prefix(15)
            .map { "\($0.surgeRank ?? 0).\($0.name)" }.joined(separator: " ")
        let reso = resonance.map(\.name).joined(separator: "、")
        let kw = keywords.prefix(12).map { "\($0.keyword)(\($0.count))" }.joined(separator: " ")
        let tagText = tags.map { "\($0.tag) \($0.count)" }.joined(separator: "、")
        return """
        【市场热度与飙升雷达 · \(period == .day ? "日榜" : "小时榜") · \(ShanghaiDate.dayFormatter.string(from: fetchedAt))】
        热股榜 Top15:\(hot)
        飙升榜 Top15:\(surge)
        热度共振(同时在榜):\(reso.isEmpty ? "无" : reso)
        异动标签统计:\(tagText)
        异动关键词热度:\(kw)
        """
    }
}

enum HeatRadarAnalyzer {
    static func run(
        period: HotListPeriod,
        hot: [HotStockItem],
        surge: [HotStockItem],
        anomalies: [AnomalyItem],
        fetchedAt: Date = Date()
    ) -> HeatRadarReport {
        var anomalyByCode: [String: AnomalyItem] = [:]
        for item in anomalies where anomalyByCode[item.thscode] == nil { anomalyByCode[item.thscode] = item }

        var points: [String: HeatRadarReport.RadarPoint] = [:]
        for item in hot {
            points[item.thscode] = .init(
                thscode: item.thscode, name: item.name, hotRank: item.rank, surgeRank: nil,
                heat: item.heatValue, rankChange: item.rank_change, trend: item.rank_trend ?? "unknown",
                resonance: false, anomalyTag: anomalyByCode[item.thscode]?.tag_name,
                keywords: anomalyByCode[item.thscode]?.keyword_list ?? []
            )
        }
        for item in surge {
            if var existing = points[item.thscode] {
                existing.surgeRank = item.rank
                existing.resonance = true
                existing.rankChange = max(existing.rankChange ?? 0, item.rank_change ?? 0)
                points[item.thscode] = existing
            } else {
                points[item.thscode] = .init(
                    thscode: item.thscode, name: item.name, hotRank: nil, surgeRank: item.rank,
                    heat: item.heatValue, rankChange: item.rank_change, trend: item.rank_trend ?? "unknown",
                    resonance: false, anomalyTag: anomalyByCode[item.thscode]?.tag_name,
                    keywords: anomalyByCode[item.thscode]?.keyword_list ?? []
                )
            }
        }
        let all = points.values.sorted { ($0.hotRank ?? 999, $0.surgeRank ?? 999) < ($1.hotRank ?? 999, $1.surgeRank ?? 999) }

        var keywordStocks: [String: [String]] = [:]
        for item in anomalies {
            for keyword in item.keyword_list { keywordStocks[keyword, default: []].append(item.stock_name) }
        }
        let keywords = keywordStocks.map { HeatRadarReport.KeywordHeat(keyword: $0.key, count: $0.value.count, stocks: $0.value) }
            .sorted { ($0.count, $0.keyword) > ($1.count, $1.keyword) }

        var tagCounts: [String: Int] = [:]
        for item in anomalies { tagCounts[item.tag_name, default: 0] += 1 }
        let tags = tagCounts.map { HeatRadarReport.TagCount(tag: $0.key, count: $0.value) }.sorted { $0.count > $1.count }

        return HeatRadarReport(
            period: period,
            points: all,
            resonance: all.filter(\.resonance).sorted { ($0.hotRank ?? 99) < ($1.hotRank ?? 99) },
            climbers: all.filter { ($0.rankChange ?? 0) > 0 }.sorted { ($0.rankChange ?? 0) > ($1.rankChange ?? 0) }.prefix(10).map { $0 },
            keywords: keywords,
            tags: tags,
            anomalies: anomalies,
            fetchedAt: fetchedAt
        )
    }
}
