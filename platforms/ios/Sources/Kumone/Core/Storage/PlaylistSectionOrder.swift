import Foundation

enum PlaylistSection: String, CaseIterable, Identifiable {
    case netease
    case qq
    case local

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .netease: return "网易云音乐"
        case .qq: return "QQ音乐"
        case .local: return "本地歌单"
        }
    }

}

struct PlaylistSectionOrder {
    static let defaultsKey = "settings.playlistSectionOrder"
    static let defaultValue: [PlaylistSection] = [.netease, .qq, .local]

    static func load(from defaults: UserDefaults = .standard) -> [PlaylistSection] {
        normalized(defaults.stringArray(forKey: defaultsKey) ?? [])
    }

    static func save(_ sections: [PlaylistSection], to defaults: UserDefaults = .standard) {
        defaults.set(sections.map(\.rawValue), forKey: defaultsKey)
    }

    static func normalized(_ raw: [String]) -> [PlaylistSection] {
        var result = raw.compactMap(PlaylistSection.init(rawValue:))
        for section in defaultValue where !result.contains(section) {
            result.append(section)
        }
        return Array(result.prefix(defaultValue.count))
    }
}
