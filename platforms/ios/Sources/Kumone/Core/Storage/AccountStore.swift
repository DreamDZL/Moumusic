import Foundation

@MainActor
final class AccountStore: ObservableObject {
    static let shared = AccountStore()

    @Published var profile: UserProfile?
    @Published var likedTrackIDs: Set<Int> = []
    @Published var userPlaylists: [PlaylistSummary] = []
    @Published var likedAlbums: [AlbumSummary] = []
    @Published var likedArtists: [ArtistSummary] = []
    @Published var isBootstrapped = false

    var isLoggedIn: Bool { NeteaseClient.shared.isLoggedIn && profile != nil }
    var hasAuthCookie: Bool { NeteaseClient.shared.isLoggedIn }
    var vipType: Int { profile?.vipType ?? 0 }

    var likedSongsPlaylist: PlaylistSummary? {
        userPlaylists.first(where: \.isLikedSongsList) ?? userPlaylists.first
    }

    var createdPlaylists: [PlaylistSummary] {
        guard let uid = profile?.userId else { return [] }
        return userPlaylists.filter { $0.creator?.userId == uid && !$0.isLikedSongsList }
    }

    var subscribedPlaylists: [PlaylistSummary] {
        guard let uid = profile?.userId else { return [] }
        return userPlaylists.filter { $0.creator?.userId != uid }
    }

    private init() {}

    func bootstrap() async {
        guard NeteaseClient.shared.isLoggedIn else {
            isBootstrapped = true
            return
        }

        do {
            profile = try await NeteaseAPI.userAccount()
            if let userID = profile?.userId {
                async let playlists = NeteaseAPI.userPlaylists(uid: userID)
                async let liked = NeteaseAPI.likedTrackIDs(uid: userID)
                userPlaylists = try await playlists
                likedTrackIDs = Set(try await liked)
            }
        } catch {
            profile = nil
            userPlaylists = []
            likedTrackIDs = []
        }
        isBootstrapped = true
    }

    func refreshLibrary() async {
        guard let userID = profile?.userId else { return }
        do {
            userPlaylists = try await NeteaseAPI.userPlaylists(uid: userID)
            likedTrackIDs = Set(try await NeteaseAPI.likedTrackIDs(uid: userID))
        } catch {
            ToastCenter.shared.show(error.localizedDescription)
        }
    }

    func refreshSublists() async {
        await refreshLibrary()
    }

    func isLiked(_ trackID: Int) -> Bool {
        likedTrackIDs.contains(trackID)
    }

    func toggleLike(trackID: Int) async {
        let liked = likedTrackIDs.contains(trackID)
        do {
            try await NeteaseAPI.likeTrack(id: trackID, like: !liked)
            if liked { likedTrackIDs.remove(trackID) } else { likedTrackIDs.insert(trackID) }
        } catch {
            ToastCenter.shared.show(error.localizedDescription)
        }
    }

    func logout() async {
        await NeteaseAPI.logout()
        profile = nil
        likedTrackIDs = []
        userPlaylists = []
        likedAlbums = []
        likedArtists = []
        isBootstrapped = true
    }

}

// MARK: - Toasts

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

@MainActor
final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()

    @Published var current: Toast?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    func show(_ message: String) {
        current = Toast(message: message)
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            current = nil
        }
    }
}
