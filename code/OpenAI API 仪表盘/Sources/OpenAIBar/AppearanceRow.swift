import SwiftUI

extension AppearanceMode {
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
        VStack(alignment: .leading, spacing: 7) {
            Text("外观模式").font(.system(size: 13))
            HStack(spacing: 10) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    let selected = selection == mode
                    Button { select(mode) } label: {
                        VStack(spacing: 5) {
                            ZStack(alignment: .topLeading) {
                                HStack(spacing: 0) {
                                    (mode == .dark ? Color(white: 0.26) : Color(white: 0.94))
                                    (mode == .light ? Color(white: 0.84) : Color(white: 0.16))
                                }
                                HStack(spacing: 3) {
                                    ForEach([Color.red, .yellow, .green], id: \.self) { color in
                                        Circle().fill(color).frame(width: 4, height: 4)
                                    }
                                }
                                .padding(6)
                            }
                            .frame(height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            HStack(spacing: 4) {
                                if selected { Image(systemName: "checkmark") }
                                Text(mode.title)
                            }
                                .font(.system(size: 12))
                                .foregroundStyle(scheme == .dark ? Color.white : .black)
                        }
                        .padding(6)
                        .frame(maxWidth: .infinity)
                        .background(Glass.inset(scheme), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(selected ? Color.brand(scheme) : Glass.hairline(scheme),
                                          lineWidth: selected ? 2 : 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(mode.title)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            Text("选择后立即生效。系统模式跟随 macOS 外观。")
                .font(.system(size: 11)).foregroundStyle(TextTone.secondary(scheme))
        }
    }
}
