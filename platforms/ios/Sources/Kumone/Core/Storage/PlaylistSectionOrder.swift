import Foundation

enum PlaylistSection: String, CaseIterable, Identifiable {
    case netease
    case qq
    case local

    var id: String { rawValue }

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
