import AppKit
import Foundation

// 构建期工具：把 LogoMark 渲染成 iconset，再由 iconutil 打成 .icns
// 用法：swiftc Logo.swift icongen.swift -o icongen && ./icongen Resources/icon.iconset

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/icon.iconset"
let fm = FileManager.default
try? fm.createDirectory(atPath: outPath, withIntermediateDirectories: true)

let specs: [(Int, String)] = [
    (16, "icon_16x16"), (32, "icon_16x16@2x"),
    (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"),
    (256, "icon_256x256"), (512, "icon_256x256@2x"),
    (512, "icon_512x512"), (1024, "icon_512x512@2x")
]

for (px, name) in specs {
    guard let data = LogoMark.pngData(size: CGFloat(px)) else {
        FileHandle.standardError.write("渲染失败: \(name)\n".data(using: .utf8)!)
        exit(1)
    }
    try data.write(to: URL(fileURLWithPath: outPath).appendingPathComponent("\(name).png"))
}

// 顺手导一张大图，给文档/预览用
if let big = LogoMark.pngData(size: 1024) {
    let parent = (outPath as NSString).deletingLastPathComponent
    try? big.write(to: URL(fileURLWithPath: parent).appendingPathComponent("AppIcon-1024.png"))
}

print("iconset 已生成: \(outPath)")
