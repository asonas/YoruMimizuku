import Foundation

enum UpdateChannel: String, CaseIterable, Identifiable {
    case stable
    case development

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stable: return "リリース"
        case .development: return "開発版"
        }
    }

    var feedURL: URL {
        switch self {
        case .stable:
            return URL(string: "https://asonas.github.io/YoruMimizuku/appcast.xml")!
        case .development:
            return URL(string: "https://asonas.github.io/YoruMimizuku/appcast-dev.xml")!
        }
    }

    var explanation: String {
        switch self {
        case .stable:
            return "v0.6.0 や v0.7.0 など、通常のリリースだけを受け取ります。"
        case .development:
            return "v0.7.0-dev.1 などの開発版も受け取ります。stable に戻しても downgrade はされません。"
        }
    }
}
