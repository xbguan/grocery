import SwiftUI

private enum AnalysisRange: Int, CaseIterable {
    case yesterday = 0
    case today = 1
    case seven = 7
    case fourteen = 14
    case thirty = 30

    var title: String {
        switch self {
        case .yesterday: return "昨天"
        case .today: return "今天"
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
        case .feature: return localized(item.feature, values: [
            "automation": "自动化", "chat": "聊天", "user_message": "对话",
            "work": "工作", "codex": "编程", "other": "其他"
        ])
        case .model: return item.model
        case .surface: return localized(item.surface, values: [
            "desktop_app": "桌面应用", "web": "网页", "mobile_app": "移动应用",
            "work": "工作界面", "codex": "编程界面", "other": "其他"
        ])
        case .trigger: return localized(item.trigger, values: [
            "user_message": "用户发起", "automation": "自动发起", "other": "其他"
        ])
        }
    }

    private func localized(_ value: String, values: [String: String]) -> String {
        values[value.lowercased()] ?? value
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
    @State private var hoveredTokenDay: Int?
    @State private var hoveredUsageDay: Int?
    @State private var hoveredToolDay: Int?
    @State private var hoveredMessageDay: Int?
    @State private var tokenPointer: CGPoint = .zero
    @State private var usagePointer: CGPoint = .zero
    @State private var toolPointer: CGPoint = .zero
    @State private var messagePointer: CGPoint = .zero

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
        let lastDate = calendar.date(byAdding: .day, value: range == .yesterday ? -1 : 0, to: today)!
        let start = calendar.date(byAdding: .day, value: 1 - max(1, range.rawValue), to: lastDate)!
        let formatter = ISO8601DateFormatter()
        let firstDay = String(formatter.string(from: start).prefix(10))
        let lastDay = String(formatter.string(from: lastDate).prefix(10))
        return data.sortedDays.filter { $0.id >= firstDay && $0.id <= lastDay }
    }

    private func rangePicker(_ values: [AnalysisRange], selected: Binding<AnalysisRange>) -> some View {
        HStack(spacing: 2) {
            ForEach(values, id: \.self) { range in
                Button { selected.wrappedValue = range } label: {
                    Text(range.title)
                        .font(.system(size: 11.5, weight: selected.wrappedValue == range ? .semibold : .regular))
                        .foregroundStyle(selected.wrappedValue == range ? Color.primary : TextTone.secondary(scheme))
                        .frame(width: values.count == 5 ? 40 : values.count == 4 ? 45 : 50, height: 25)
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
                barChart(points)
                axis(points, insetLeading: 44)
            } else {
                unavailable("暂未取得此时段的 Tokens 数据")
            }
        }
        .padding(14).glassCard()
    }

    private var usageCard: some View {
        let points = days(usageRange)
        let names = topUsageNames(points)
        let totals = usageTotals(points)
        let overall = totals.values.reduce(0, +)
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
                usageLegend(names, totals: totals, overall: overall)
            } else {
                unavailable("暂未取得此时段的用量历史")
            }
        }
        .padding(14).glassCard()
    }

    private var toolsCard: some View {
        let points = days(toolRange)
        let total = points.reduce(0) { $0 + $1.tools.values.reduce(0, +) }
        let series = topSeries(points, values: { $0.tools })
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                title("工具活动")
                Spacer()
                rangePicker([.seven, .thirty], selected: $toolRange)
            }
            if data.hasTools, !series.isEmpty {
                metric("工具调用", total)
                lineChart(series, points: points, hoveredDay: $hoveredToolDay,
                          pointer: $toolPointer, unit: "次",
                          dailyTotal: { $0.tools.values.reduce(0, +) })
                axis(points, insetLeading: 36)
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
                    lineChart(series, points: points, hoveredDay: $hoveredMessageDay,
                              pointer: $messagePointer, unit: "条",
                              dailyTotal: { $0.messages ?? 0 })
                    axis(points, insetLeading: 36)
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

    private func barChart(_ points: [SubscriptionDay]) -> some View {
        let step = axisStep(Double(points.compactMap(\.tokens).max() ?? 0))
        let peak = Double(step * 3)
        return HStack(spacing: 6) {
            VStack(alignment: .trailing, spacing: 0) {
                ForEach((0...3).reversed(), id: \.self) { index in
                    Text(Fmt.tokens(step * index))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    if index > 0 { Spacer(minLength: 0) }
                }
            }
            .font(.system(size: 9).monospacedDigit())
            .foregroundStyle(TextTone.tertiary(scheme))
            .frame(width: 38, height: 105)

            GeometryReader { geometry in
                let slot = geometry.size.width / CGFloat(max(points.count, 1))
                let barWidth = min(14, max(4, slot * 0.58))
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                        Rectangle()
                            .fill(index == points.count - 1 ? Color.brand(scheme) : Color.brand(scheme).opacity(0.58))
                            .frame(width: barWidth)
                            .frame(height: max(2, geometry.size.height * Double(point.tokens ?? 0) / peak))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .background { chartGrid() }
                .overlay {
                    if let index = hoveredTokenDay, points.indices.contains(index) {
                        hoverCard(date: points[index].id, summary: "当天 Tokens",
                                  rows: [("用量", "\((points[index].tokens ?? 0).formatted())", Color.brand(scheme))])
                            .frame(width: 168)
                            .position(tooltipPosition(tokenPointer, in: geometry.size, rows: 1))
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        tokenPointer = location
                        hoveredTokenDay = min(points.count - 1, max(0, Int(location.x / slot)))
                    case .ended:
                        hoveredTokenDay = nil
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
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .background {
                chartGrid()
            }
            .overlay {
                if let index = hoveredUsageDay, points.indices.contains(index) {
                    let grouped = usageValues(points[index])
                    let dayTotal = grouped.values.reduce(0, +)
                    let rows = names.enumerated().map { colorIndex, name in
                        (name, percent(grouped[name] ?? 0, total: dayTotal), usageColor(colorIndex))
                    }
                    hoverCard(date: points[index].id, summary: "当日用量占比", rows: rows)
                        .frame(width: 168)
                        .position(tooltipPosition(usagePointer, in: geometry.size, rows: rows.count))
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    usagePointer = location
                    hoveredUsageDay = min(points.count - 1, max(0, Int(location.x / slot)))
                case .ended:
                    hoveredUsageDay = nil
                }
            }
        }
        .frame(height: 105)
    }

    private func lineChart(_ series: [ChartSeries], points: [SubscriptionDay],
                           hoveredDay: Binding<Int?>, pointer: Binding<CGPoint>, unit: String,
                           dailyTotal: @escaping (SubscriptionDay) -> Int) -> some View {
        let step = axisStep(series.flatMap(\.values).max() ?? 0)
        let peak = Double(step * 3)
        return HStack(spacing: 6) {
            VStack(alignment: .trailing, spacing: 0) {
                ForEach((0...3).reversed(), id: \.self) { index in
                    Text((step * index).formatted())
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    if index > 0 { Spacer(minLength: 0) }
                }
            }
            .font(.system(size: 9).monospacedDigit())
            .foregroundStyle(TextTone.tertiary(scheme))
            .frame(width: 30, height: 105)

            GeometryReader { geometry in
                ZStack {
                    chartGrid()
                    if let index = hoveredDay.wrappedValue, points.indices.contains(index) {
                        Rectangle()
                            .fill(Color.primary.opacity(0.20))
                            .frame(width: 1)
                            .position(x: geometry.size.width * CGFloat(index) / CGFloat(max(1, points.count - 1)),
                                      y: geometry.size.height / 2)
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
                .overlay {
                    if let index = hoveredDay.wrappedValue, points.indices.contains(index) {
                        let rows = series.map { item in
                            (item.id, "\(Int(item.values[index]).formatted()) \(unit)", item.color)
                        }
                        let total = dailyTotal(points[index])
                        hoverCard(date: points[index].id, summary: "合计 \(total.formatted()) \(unit)", rows: rows)
                            .frame(width: 168)
                            .position(tooltipPosition(pointer.wrappedValue, in: geometry.size,
                                                      rows: rows.count))
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        pointer.wrappedValue = location
                        let position = location.x / max(1, geometry.size.width)
                        hoveredDay.wrappedValue = min(points.count - 1,
                                                       max(0, Int((position * CGFloat(points.count - 1)).rounded())))
                    case .ended:
                        hoveredDay.wrappedValue = nil
                    }
                }
            }
        }
        .frame(height: 105)
    }

    private func axis(_ points: [SubscriptionDay], insetLeading: CGFloat = 0) -> some View {
        HStack {
            if points.count == 1 {
                Text(shortDate(points[0].id)).frame(maxWidth: .infinity)
            } else {
                Text(shortDate(points.first?.id))
                Spacer()
                if points.count > 3 { Text(shortDate(points[points.count / 2].id)); Spacer() }
                Text(shortDate(points.last?.id))
            }
        }
        .padding(.leading, insetLeading)
        .font(.system(size: 9.5).monospacedDigit())
        .foregroundStyle(TextTone.tertiary(scheme))
    }

    private func chartGrid() -> some View {
        VStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { index in
                Rectangle().fill(Glass.hairline(scheme)).frame(height: 1)
                if index < 3 { Spacer(minLength: 0) }
            }
        }
    }

    private func axisStep(_ maximum: Double) -> Int {
        let target = max(1, maximum / 3)
        let magnitude = pow(10, floor(log10(target)))
        let scaled = target / magnitude
        let multiplier: Double = scaled <= 1 ? 1 : scaled <= 2 ? 2 : scaled <= 2.5 ? 2.5 : scaled <= 5 ? 5 : 10
        return max(1, Int(multiplier * magnitude))
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

    private func usageLegend(_ names: [String], totals: [String: Double], overall: Double) -> some View {
        LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], alignment: .leading, spacing: 5) {
            ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(usageColor(index))
                        .frame(width: 7, height: 7)
                    Text(name).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 2)
                    Text(percent(totals[name] ?? 0, total: overall))
                        .monospacedDigit().fixedSize()
                }
                .font(.system(size: 9.5))
                .foregroundStyle(TextTone.secondary(scheme))
            }
        }
    }

    private func hoverCard(date: String, summary: String,
                           rows: [(String, String, Color)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(date.replacingOccurrences(of: "-", with: "/")) · \(summary)")
                .font(.system(size: 9.5, weight: .semibold))
                .lineLimit(1)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 4) {
                    Circle().fill(row.2).frame(width: 5, height: 5)
                    Text(row.0).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 2)
                    Text(row.1).monospacedDigit().fixedSize()
                }
            }
        }
        .font(.system(size: 9))
        .foregroundStyle(Color.primary)
        .padding(7)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.97))
                .overlay {
                    RoundedRectangle(cornerRadius: 8).fill(Glass.fill(scheme))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Glass.stroke(scheme), lineWidth: 1)
        }
        .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.15), radius: 6, x: 0, y: 3)
    }

    private func tooltipPosition(_ pointer: CGPoint, in size: CGSize, rows: Int) -> CGPoint {
        let halfWidth: CGFloat = 84
        let halfHeight = CGFloat(29 + rows * 13) / 2
        let right = pointer.x + 12 + halfWidth
        let x = right + halfWidth <= size.width ? right : pointer.x - 12 - halfWidth
        return CGPoint(x: min(max(halfWidth, x), size.width - halfWidth),
                       y: min(max(halfHeight, pointer.y), size.height - halfHeight))
    }

    private func percent(_ value: Double, total: Double) -> String {
        guard total > 0 else { return "0%" }
        return (value / total).formatted(.percent.precision(.fractionLength(0)))
    }

    private func usageValues(_ day: SubscriptionDay) -> [String: Double] {
        var result: [String: Double] = [:]
        for item in day.usage { result[usageGroup.name(item), default: 0] += max(0, item.value) }
        return result
    }

    private func topUsageNames(_ points: [SubscriptionDay]) -> [String] {
        let totals = usageTotals(points)
        return Array(totals.sorted {
            $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
        }.prefix(4).map(\.key))
    }

    private func usageTotals(_ points: [SubscriptionDay]) -> [String: Double] {
        var totals: [String: Double] = [:]
        for day in points {
            for (name, value) in usageValues(day) { totals[name, default: 0] += value }
        }
        return totals
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
