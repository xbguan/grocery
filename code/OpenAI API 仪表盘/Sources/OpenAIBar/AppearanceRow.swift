import SwiftUI

enum AppearanceMode: String, Codable, CaseIterable {
    case system, dark, light

    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .dark: return NSAppearance(named: .darkAqua)
        case .light: return NSAppearance(named: .aqua)
        }
    }

    var title: String {
        switch self {
        case .system: return "系统"
        case .dark: return "深色"
        case .light: return "浅色"
        }
    }
}

struct AppearanceRow: View {
    let selection: AppearanceMode
    let select: (AppearanceMode) -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text("外观模式")
                .font(.system(size: 11.5, weight: .medium))
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 2) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        let selected = selection == mode
                        Button {
                            select(mode)
                        } label: {
                            HStack(spacing: 4) {
                                if selected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                Text(mode.title)
                            }
                            .font(.system(size: 12, weight: selected ? .semibold : .regular))
                            .frame(width: 62, height: 24)
                            .background(selected ? Color.brand(scheme).opacity(0.24) : .clear,
                                        in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(mode.title)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(2)
                .background(Glass.inset(scheme), in: RoundedRectangle(cornerRadius: 8))
                Text(selection == .system ? "跟随 macOS 外观自动切换" : "始终使用" + selection.title + "外观")
                    .font(.system(size: 11))
                    .foregroundStyle(TextTone.secondary(scheme))
            }
        }
    }
}
