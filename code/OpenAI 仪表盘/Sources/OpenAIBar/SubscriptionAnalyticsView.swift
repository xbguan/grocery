import SwiftUI

private enum AnalysisRange: Int, CaseIterable {
    case today = 1
    case seven = 7
    case fourteen = 14
    case thirty = 30

    var title: String {
        switch self {
        case .today: return "今日"
        case .seven: return "7 天"
        case .fourteen: return "14 天"
        case .thirty: return "30 天"
        }
    }
}

private enum UsageGroup: String, CaseIterable {
    case feature = "按功能"
    case model = "按模型"
    case surface = "按界面"
    case trigger = "按轮次发起方式"

    func name(_ item: UsageAttribution) -> String {
        switch self {
        case .feature: return item.feature
        case .model: return item.model
        case .surface: return item.surface
        case .trigger: return item.trigger
        }
    }
}

private struct ChartSeries: Identifiable {
    let id: String
    let values: [Double]
    let color: Color
    let styleIndex: Int
}

struct SubscriptionAnalyticsView: View {
    @Environment(\.colorScheme) private var scheme
    let data: SubscriptionSnapshot
    @State private var tokenRange: AnalysisRange = .seven
    @State private var usageRange: AnalysisRange = .seven
    @State private var toolRange: AnalysisRange = .seven
    @State private var messageRange: AnalysisRange = .seven
    @State private var usageGroup: UsageGroup = .feature
    @State private var messageByClient = false

    var body: some View {
        VStack(spacing: UI.gap) {
            tokensCard
            usageCard
            toolsCard
            messagesCard
        }
    }

    private func days(_ range: AnalysisRange) -> [SubscriptionDay] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.startOfDay(for: .now)
        let start = calendar.date(byAdding: .day, value: 1 - range.rawValue, to: today)!
        let formatter = ISO8601DateFormatter()
        let firstDay = String(formatter.string(from: start).prefix(10))
        let lastDay = String(formatter.string(from: today).prefix(10))
        return data.sortedDays.filter { $0.id >= firstDay && $0.id <= lastDay }
    }

    private func rangePicker(_ values: [AnalysisRange], selected: Binding<AnalysisRange>) -> some View {
        HStack(spacing: 2) {
            ForEach(values, id: \.self) { range in
                Button { selected.wrappedValue = range } label: {
                    Text(range.title)
                        .font(.system(size: 11.5, weight: selected.wrappedValue == range ? .semibold : .regular))
                        .foregroundStyle(selected.wrappedValue == range ? Color.primary : TextTone.secondary(scheme))
                        .frame(width: values.count == 4 ? 45 : 50, height: 25)
                        .background {
                            if selected.wrappedValue == range {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Glass.fill(scheme))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(Glass.stroke(scheme), lineWidth: 0.8)
                                    }
                                    .shadow(color: .black.opacity(scheme == .dark ? 0.16 : 0.10),
                                            radius: 3, x: 0, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Glass.inset(scheme), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Glass.hairline(scheme), lineWidth: 0.8)
        }
    }

    private func groupMenuLabel(_ value: String) -> some View {
        HStack(spacing: 6) {
            Text(value).lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
        }
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 10)
        .frame(height: 31)
        .background(Glass.fill(scheme), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Glass.stroke(scheme), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(scheme == .dark ? 0.14 : 0.08), radius: 3, x: 0, y: 1)
    }

    private var tokensCard: some View {
        let points = days(tokenRange)
        let total = points.compactMap(\.tokens).reduce(0, +)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                title("Tokens 用量")
                Spacer(minLength: 4)
                rangePicker(AnalysisRange.allCases, selected: $tokenRange)
            }
            if data.hasTokens, points.contains(where: { $0.tokens != nil }) {
                Text(Fmt.tokens(total))
                    .font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit())
                    .accessibilityLabel("已用 Tokens \(total)")
                Text("已用 Tokens · UTC")
                    .font(.system(size: 10.5))
                    .foregroundStyle(TextTone.secondary(scheme))
                barChart(points.map { Double($0.tokens ?? 0) })
                axis(points)
            } else {
                unavailable("暂未取得此时段的 Tokens 数据")
            }
        }
        .padding(14).glassCard()
    }

    private var usageCard: some View {
        let points = days(usageRange)
        let names = topUsageNames(points)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                title("用量历史记录")
                Spacer(minLength: 3)
                Menu {
                    ForEach(UsageGroup.allCases, id: \.self) { group in
                        Button(group.rawValue) { usageGroup = group }
                    }
                } label: {
                    groupMenuLabel(usageGroup.rawValue)
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                rangePicker([.seven, .thirty], selected: $usageRange)
            }
            if data.hasUsageHistory, points.contains(where: { !$0.usage.isEmpty }) {
                Text("套餐用量占比 · UTC")
                    .font(.system(size: 10.5))
                    .foregroundStyle(TextTone.secondary(scheme))
                stackedUsageChart(points, names: names)
                axis(points)
                legend(names.map { ($0, usageColor(names.firstIndex(of: $0) ?? 0)) })
            } else {
                unavailable("暂未取得此时段的用量历史")
            }
        }
        .padding(14).glassCard()
    }

    private var toolsCard: some View {
        let points = days(toolRange)
        let total = points.reduce(0) { $0 + $1.plugins.values.reduce(0, +) }
        let series = topSeries(points, values: { $0.tools })
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                title("工具活动")
                Spacer()
                rangePicker([.seven, .thirty], selected: $toolRange)
            }
            if data.hasTools, !series.isEmpty {
                metric("插件调用", total)
                lineChart(series)
                axis(points)
                legend(series.map { ($0.id, $0.color) }, markers: true)
            } else {
                unavailable("暂未取得此时段的工具活动")
            }
        }
        .padding(14).glassCard()
    }

    private var messagesCard: some View {
        let points = days(messageRange)
        let total = points.compactMap(\.messages).reduce(0, +)
        let series = topSeries(points, values: { messageByClient ? $0.messageClients : $0.messageModels })
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                title("消息")
                Spacer(minLength: 3)
                Menu {
                    Button("按模型") { messageByClient = false }
                    Button("按使用端") { messageByClient = true }
                } label: {
                    groupMenuLabel(messageByClient ? "按使用端" : "按模型")
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                rangePicker([.seven, .thirty], selected: $messageRange)
            }
            if data.hasMessages, points.contains(where: { $0.messages != nil }) {
                metric("消息", total)
                if !series.isEmpty {
                    lineChart(series)
                    axis(points)
                    legend(series.map { ($0.id, $0.color) }, markers: true)
                } else {
                    unavailable("该时段暂无模型明细")
                }
            } else {
                unavailable("暂未取得此时段的消息数据")
            }
        }
        .padding(14).glassCard()
    }

    private func title(_ value: String) -> some View {
        Text(value).font(.system(size: 12.5, weight: .semibold))
    }

    private func metric(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 10.5)).foregroundStyle(TextTone.secondary(scheme))
            Text(value.formatted())
                .font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit())
        }
    }

    private func unavailable(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 11))
            .foregroundStyle(TextTone.secondary(scheme))
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .center)
    }

    private func barChart(_ values: [Double]) -> some View {
        let maxValue = max(values.max() ?? 0, 1)
        return GeometryReader { geometry in
            let slot = geometry.size.width / CGFloat(max(values.count, 1))
            let barWidth = min(14, max(4, slot * 0.58))
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    RoundedRectangle(cornerRadius: barWidth / 2, style: .continuous)
                        .fill(index == values.count - 1 ? Color.brand(scheme) : Color.brand(scheme).opacity(0.58))
                        .frame(width: barWidth)
                        .frame(height: max(2, geometry.size.height * value / maxValue))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .background(alignment: .bottom) {
                VStack {
                    ForEach(0..<4, id: \.self) { _ in
                        Rectangle().fill(Glass.hairline(scheme)).frame(height: 1)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .frame(height: 105)
    }

    private func stackedUsageChart(_ points: [SubscriptionDay], names: [String]) -> some View {
        let totals = points.map { point in
            let grouped = usageValues(point)
            return names.reduce(0) { $0 + (grouped[$1] ?? 0) }
        }
        let peak = max(totals.max() ?? 0, 0.001)
        return GeometryReader { geometry in
            let slot = geometry.size.width / CGFloat(max(points.count, 1))
            let barWidth = min(14, max(4, slot * 0.58))
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    let grouped = usageValues(point)
                    VStack(spacing: 0) {
                        ForEach(Array(names.enumerated().reversed()), id: \.offset) { colorIndex, name in
                            let height = max(0, geometry.size.height * (grouped[name] ?? 0) / peak)
                            Rectangle()
                                .fill(usageColor(colorIndex))
                                .frame(height: height)
                                .overlay(alignment: .top) {
                                    if height > 1 {
                                        Rectangle()
                                            .fill(Color.white.opacity(scheme == .dark ? 0.30 : 0.75))
                                            .frame(height: 0.5)
                                    }
                                }
                        }
                    }
                    .frame(width: barWidth)
                    .frame(height: geometry.size.height * totals[index] / peak, alignment: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: barWidth / 2, style: .continuous))
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: 105)
    }

    private func lineChart(_ series: [ChartSeries]) -> some View {
        let peak = max(series.flatMap(\.values).max() ?? 0, 1)
        return GeometryReader { geometry in
            ZStack {
                ForEach(0..<4, id: \.self) { index in
                    Rectangle().fill(Glass.hairline(scheme)).frame(height: 1)
                        .position(x: geometry.size.width / 2, y: geometry.size.height * CGFloat(index) / 3)
                }
                ForEach(series) { item in
                    Path { path in
                        for (index, value) in item.values.enumerated() {
                            let x = geometry.size.width * CGFloat(index) / CGFloat(max(1, item.values.count - 1))
                            let y = geometry.size.height * (1 - CGFloat(value / peak))
                            if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                            else { path.addLine(to: CGPoint(x: x, y: y)) }
                        }
                    }
                    .stroke(item.color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    ForEach(Array(item.values.enumerated()), id: \.offset) { index, value in
                        if index % max(1, item.values.count / 10) == 0 || index == item.values.count - 1 {
                            Image(systemName: markerSymbol(item.styleIndex))
                                .font(.system(size: 7, weight: .semibold))
                                .foregroundStyle(item.color)
                                .accessibilityHidden(true)
                                .position(
                                    x: geometry.size.width * CGFloat(index) / CGFloat(max(1, item.values.count - 1)),
                                    y: geometry.size.height * (1 - CGFloat(value / peak))
                                )
                        }
                    }
                }
            }
        }
        .frame(height: 105)
    }

    private func axis(_ points: [SubscriptionDay]) -> some View {
        HStack {
            Text(shortDate(points.first?.id))
            Spacer()
            if points.count > 3 { Text(shortDate(points[points.count / 2].id)); Spacer() }
            Text(shortDate(points.last?.id))
        }
        .font(.system(size: 9.5).monospacedDigit())
        .foregroundStyle(TextTone.tertiary(scheme))
    }

    private func shortDate(_ date: String?) -> String {
        guard let date, date.count >= 10 else { return "" }
        return String(date.suffix(5)).replacingOccurrences(of: "-", with: "/")
    }

    private func legend(_ items: [(String, Color)], markers: Bool = false) -> some View {
        LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], alignment: .leading, spacing: 5) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(spacing: 5) {
                    if markers {
                        Image(systemName: markerSymbol(index))
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundStyle(item.1)
                            .frame(width: 7, height: 7)
                            .accessibilityHidden(true)
                    } else {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(item.1)
                            .frame(width: 7, height: 7)
                    }
                    Text(item.0).lineLimit(1)
                }
                .font(.system(size: 9.5))
                .foregroundStyle(TextTone.secondary(scheme))
            }
        }
    }

    private func usageValues(_ day: SubscriptionDay) -> [String: Double] {
        var result: [String: Double] = [:]
        for item in day.usage { result[usageGroup.name(item), default: 0] += max(0, item.value) }
        return result
    }

    private func topUsageNames(_ points: [SubscriptionDay]) -> [String] {
        var totals: [String: Double] = [:]
        for day in points {
            for (name, value) in usageValues(day) { totals[name, default: 0] += value }
        }
        return Array(totals.sorted {
            $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
        }.prefix(4).map(\.key))
    }

    private func usageColor(_ index: Int) -> Color {
        switch index {
        case 0: return Color.brand(scheme)
        case 1: return Color(nsColor: .systemBlue)
        case 2: return Color(nsColor: .systemOrange)
        default: return Color(nsColor: .systemPurple)
        }
    }

    private func markerSymbol(_ index: Int) -> String {
        switch index {
        case 0: return "circle.fill"
        case 1: return "square.fill"
        case 2: return "diamond.fill"
        default: return "triangle.fill"
        }
    }

    private func topSeries(_ points: [SubscriptionDay],
                           values: (SubscriptionDay) -> [String: Int]) -> [ChartSeries] {
        var totals: [String: Int] = [:]
        for day in points {
            for (name, value) in values(day) { totals[name, default: 0] += value }
        }
        return totals.sorted {
            $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
        }.prefix(4).enumerated().map { index, item in
            ChartSeries(id: item.key,
                        values: points.map { Double(values($0)[item.key] ?? 0) },
                        color: usageColor(index),
                        styleIndex: index)
        }
    }
}
