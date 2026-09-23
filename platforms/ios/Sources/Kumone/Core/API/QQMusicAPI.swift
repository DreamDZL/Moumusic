import CommonCrypto
import Combine
import Foundation
import Security

/// Small QQ Music account surface used by the iOS library.
///
/// QQ's personal-library endpoints are not part of the public catalogue API;
/// this client is intentionally isolated so changes in that protocol do not
/// leak into the player or LX source bridge.
@MainActor
final class QQMusicAPI: ObservableObject {
    static let shared = QQMusicAPI()

    struct Playlist: Codable, Hashable, Identifiable {
        let id: Int
        let dirID: Int
        let name: String
        let coverURL: String?
        let trackCount: Int
        let isLiked: Bool
    }

    struct Detail {
        let playlist: Playlist
        let tracks: [Track]
    }

    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var isLoggedIn = false

    private let session: URLSession
    private let keychainKey = "moumusic.qqmusic.cookie"
    private var cookie: String?

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        session = URLSession(configuration: configuration)
        cookie = Self.readKeychain(key: keychainKey)
        isLoggedIn = Self.validCookie(cookie)
    }

    func setCookie(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        cookie = trimmed.isEmpty ? nil : trimmed
        isLoggedIn = Self.validCookie(cookie)
        if let cookie, !cookie.isEmpty {
            Self.writeKeychain(cookie, key: keychainKey)
        } else {
            Self.deleteKeychain(key: keychainKey)
            playlists = []
        }
    }

    func logout() {
        cookie = nil
        playlists = []
        isLoggedIn = false
        Self.deleteKeychain(key: keychainKey)
    }

    func refreshPlaylists() async throws {
        guard let cookie, let uin = Self.extractUIN(cookie) else {
            throw QQMusicError.notLoggedIn
        }
        let payload: [String: Any] = [
            "comm": ["ct": 24, "cv": 1800],
            "req_0": [
                "module": "music.musicasset.PlaylistBaseRead",
                "method": "GetPlaylistByUin",
                "param": ["uin": uin],
            ],
        ]
        let root = try await request(payload)
        guard let rows = (((root["req_0"] as? [String: Any])?["data"] as? [String: Any])?["v_playlist"] as? [[String: Any]]) else {
            throw QQMusicError.invalidResponse
        }
        playlists = rows.compactMap(Self.playlist(from:))
            .filter { $0.dirID != 202 && $0.dirID != 205 && $0.dirID != 206 }
    }

    func detail(_ playlist: Playlist, page: Int = 0, pageSize: Int = 100) async throws -> Detail {
        guard let cookie, let euin = Self.extractEuin(cookie) else {
            throw QQMusicError.notLoggedIn
        }
        let payload: [String: Any] = [
            "comm": ["ct": 24, "cv": 1800],
            "req_0": [
                "module": "music.srfDissInfo.DissInfo",
                "method": "CgiGetDiss",
                "param": [
                    "disstid": playlist.id,
                    "dirid": playlist.dirID,
                    "tag": true,
                    "song_begin": page * pageSize,
                    "song_num": pageSize,
                    "userinfo": true,
                    "orderlist": true,
                    "enc_host_uin": euin,
                ],
            ],
        ]
        let root = try await request(payload)
        let data = (((root["req_0"] as? [String: Any])?["data"] as? [String: Any])) ?? [:]
        let rows = data["songlist"] as? [[String: Any]] ?? []
        return Detail(playlist: playlist, tracks: rows.compactMap(Self.track(from:)))
    }

    func remove(_ track: Track, from playlist: Playlist) async throws {
        guard let cookie else { throw QQMusicError.notLoggedIn }
        let songID = sourceSongID(track)
        let payload: [String: Any] = [
            "comm": authenticatedWebComm(cookie),
            "req_0": [
                "module": "music.musicasset.PlaylistDetailWrite",
                "method": "DelSonglist",
                "param": [
                    "dirId": playlist.dirID,
                    "tid": playlist.id,
                    "bFmtUtf8": true,
                    "v_songInfo": [["songId": songID, "songType": songType(track)]],
                ],
            ],
        ]
        let root = try await request(payload)
        try Self.requireSuccess(root)
    }

    func add(_ track: Track, to playlist: Playlist) async throws {
        guard let cookie else { throw QQMusicError.notLoggedIn }
        let songID = sourceSongID(track)
        let payload: [String: Any] = [
            "comm": authenticatedWebComm(cookie),
            "req_0": [
                "module": "music.musicasset.PlaylistDetailWrite",
                "method": "AddSonglist",
                "param": [
                    "dirId": playlist.dirID,
                    "tid": playlist.id,
                    "bFmtUtf8": true,
                    "v_songInfo": [["songId": songID, "songType": songType(track)]],
                ],
            ],
        ]
        try Self.requireSuccess(try await request(payload))
    }

    enum QQMusicError: LocalizedError {
        case notLoggedIn
        case invalidResponse
        case requestFailed
        case operationRejected(Int)

        var errorDescription: String? {
            switch self {
            case .notLoggedIn: return "请先登录 QQ 音乐"
            case .invalidResponse: return "QQ 音乐返回了无法识别的数据"
            case .requestFailed: return "QQ 音乐请求失败，请重新登录后重试"
            case .operationRejected(let code):
                return "QQ 音乐未接受此次歌单操作（错误码：\(code)），请确认目标歌单可编辑后重试"
            }
        }
    }

    private func sourceSongID(_ track: Track) -> Int {
        Int(track.sourceMetadata["songId"] ?? track.sourceMetadata["id"] ?? "") ?? track.id
    }

    private func songType(_ track: Track) -> Int {
        Int(track.sourceMetadata["songType"] ?? track.sourceMetadata["song_type"] ?? "") ?? 13
    }

    private func authenticatedWebComm(_ cookie: String) -> [String: Any] {
        let ticket = Self.cookieValue("qqmusic_key", in: cookie)
            ?? Self.cookieValue("qm_keyst", in: cookie)
            ?? Self.cookieValue("p_skey", in: cookie)
            ?? Self.cookieValue("skey", in: cookie)
            ?? ""
        let uin = Self.numericUIN(cookie) ?? "0"
        let gtk = Self.hash33(ticket)
        return [
            "ct": 24,
            "cv": 4747474,
            "platform": "yqq.json",
            "uin": uin,
            "authst": ticket,
            "g_tk": gtk,
            "g_tk_new_20200303": gtk,
            "format": "json",
            "inCharset": "utf-8",
            "outCharset": "utf-8",
            "notice": 0,
            "need_new_code": 1,
        ]
    }

    private static func numericUIN(_ cookie: String) -> String? {
        for key in ["wxuin", "qqmusic_uin", "uin", "ied_qq"] {
            guard let value = cookieValue(key, in: cookie) else { continue }
            let digits = value.hasPrefix("o") ? String(value.dropFirst()) : value
            if !digits.isEmpty, digits.allSatisfy(\.isNumber) { return digits }
        }
        return nil
    }

    private static func cookieValue(_ key: String, in cookie: String) -> String? {
        cookie.split(separator: ";").lazy.compactMap { part -> String? in
            let pair = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2,
                  pair[0].trimmingCharacters(in: .whitespaces) == key else { return nil }
            return pair[1].trimmingCharacters(in: .whitespaces)
        }.first
    }

    private static func hash33(_ value: String) -> Int {
        value.utf16.reduce(5381) { hash, character in
            ((hash << 5) &+ hash &+ Int(character)) & 0x7fffffff
        }
    }

    private func request(_ payload: [String: Any]) async throws -> [String: Any] {
        guard let cookie, let data = try? JSONSerialization.data(withJSONObject: payload),
              let sign = LXCatalogService.zzcSign(data) else { throw QQMusicError.requestFailed }
        var components = URLComponents(string: "https://u.y.qq.com/cgi-bin/musics.fcg")!
        components.queryItems = [URLQueryItem(name: "sign", value: sign)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("https://y.qq.com", forHTTPHeaderField: "Origin")
        request.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
        request.setValue("QQMusic 14090508(android 12)", forHTTPHeaderField: "User-Agent")
        let (body, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let root = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            throw QQMusicError.requestFailed
        }
        return root
    }

    private static func requireSuccess(_ root: [String: Any]) throws {
        let requestResult = root["req_0"] as? [String: Any]
        let data = requestResult?["data"] as? [String: Any]
        let codes = [root["code"], requestResult?["code"], requestResult?["ret"], data?["retCode"]]
            .compactMap { int($0) }
        guard !codes.isEmpty else { throw QQMusicError.invalidResponse }
        if let code = codes.first(where: { $0 != 0 }) {
            throw QQMusicError.operationRejected(code)
        }
    }

    private static func playlist(from row: [String: Any]) -> Playlist? {
        guard let id = int(row["tid"]), let name = row["dirName"] as? String else { return nil }
        let dirID = int(row["dirId"]) ?? 0
        return Playlist(id: id, dirID: dirID, name: name,
                        coverURL: row["picUrl"] as? String ?? row["bigpicUrl"] as? String,
                        trackCount: int(row["songNum"]) ?? 0, isLiked: dirID == 201)
    }

    private static func track(from row: [String: Any]) -> Track? {
        guard let id = int(row["id"] ?? row["songid"]),
              let name = (row["title"] as? String) ?? (row["name"] as? String) else { return nil }
        let singers = (row["singer"] as? [[String: Any]] ?? []).compactMap { singer -> ArtistRef? in
            guard let name = singer["name"] as? String else { return nil }
            return ArtistRef(id: int(singer["id"]) ?? 0, name: name)
        }
        let album = row["album"] as? [String: Any]
        let albumMid = (album?["mid"] as? String)
            ?? (album?["pmid"] as? String)
            ?? (row["albummid"] as? String)
        let coverURL = albumMid.flatMap { mid -> String? in
            guard !mid.isEmpty else { return nil }
            return "https://y.gtimg.cn/music/photo_new/T002R300x300M000\(mid).jpg"
        }
        return Track(id: id, name: name, artists: singers,
                     album: AlbumRef(id: int(album?["id"]) ?? 0,
                                     name: album?["name"] as? String ?? "",
                                     picUrl: coverURL),
                     durationMS: (int(row["interval"]) ?? 0) * 1000,
                     source: "tx",
                     sourceMetadata: ["songmid": row["songmid"] as? String ?? "",
                                      "songId": String(id),
                                      "songType": String(int(row["type"] ?? row["songType"]) ?? 13)])
    }

    private static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private static func extractUIN(_ cookie: String) -> String? {
        let pattern = #"(?:^|;)\s*(?:uin|wxUin|wxuin)=(\d+|o[A-Za-z0-9_-]+)"#
        return firstMatch(pattern, in: cookie)
    }

    private static func extractEuin(_ cookie: String) -> String? {
        firstMatch(#"(?:^|;)\s*euin=([^;]+)"#, in: cookie)
    }

    private static func firstMatch(_ pattern: String, in value: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.firstMatch(in: value, range: range).flatMap {
            guard $0.numberOfRanges > 1, let result = Range($0.range(at: 1), in: value) else { return nil }
            return String(value[result])
        }
    }

    private static func validCookie(_ cookie: String?) -> Bool {
        guard let cookie else { return false }
        return extractUIN(cookie) != nil
            && (cookie.contains("qqmusic_key") || cookie.contains("p_skey"))
    }

    private static func query(_ key: String, _ service: String = "moumusic") -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrAccount as String: key,
         kSecAttrService as String: service]
    }

    private static func readKeychain(key: String) -> String? {
        var query = query(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeKeychain(_ value: String, key: String) {
        let data = Data(value.utf8)
        var query = query(key)
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func deleteKeychain(key: String) {
        SecItemDelete(query(key) as CFDictionary)
    }
}
