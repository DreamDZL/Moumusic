import SwiftUI
import UniformTypeIdentifiers

struct LocalPlaylistsView: View {
    @StateObject private var store = LocalPlaylistStore.shared
    @EnvironmentObject private var account: AccountStore
    @StateObject private var qqMusic = QQMusicAPI.shared
    @State private var showImport = false
    @State private var showQQLogin = false
    @State private var showQQWebLogin = false
    @State private var showNeteaseWebLogin = false
    @State private var showCreate = false
    @State private var newName = ""
    @State private var onlineErrorMessage: String?
    @State private var isReorderingSections = false
    @State private var sectionOrder = PlaylistSectionOrder.load()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(sectionOrder) { section in
                    sectionView(section)
                        .overlay {
                            if isReorderingSections {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Theme.accent.opacity(0.35), lineWidth: 1)
                                    .allowsHitTesting(false)
                            }
                        }
                        .onDrag {
                            guard isReorderingSections else { return NSItemProvider() }
                            return NSItemProvider(object: section.rawValue as NSString)
                        }
                        .onDrop(
                            of: [.text],
                            delegate: PlaylistSectionDropDelegate(
                                target: section,
                                order: $sectionOrder,
                                isEnabled: $isReorderingSections
                            )
                        )
                }
            }
            .padding(.vertical, 14)
            PlayerClearanceSpacer()
        }
        .navigationTitle("歌单")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    withAnimation(AppAnimation.standard) {
                        isReorderingSections.toggle()
                    }
                } label: {
                    Label(
                        isReorderingSections ? "完成排序" : "排序",
                        systemImage: isReorderingSections ? "checkmark" : "arrow.up.arrow.down"
                    )
                }
                Button {
                    showImport = true
                } label: {
                    Label("导入歌单", systemImage: "square.and.arrow.down")
                }
                Button {
                    showCreate = true
                } label: {
                    Label("新建歌单", systemImage: "plus")
                }
            }
        }
        .task {
            if !account.isBootstrapped { await account.bootstrap() }
        }
        .refreshable {
            await refreshOnlinePlaylists()
        }
        .sheet(isPresented: $showImport) {
            ImportPlaylistSheet()
        }
        .alert("新建本地歌单", isPresented: $showCreate) {
            TextField("歌单名称", text: $newName)
            Button("创建") {
                _ = store.create(name: newName)
                newName = ""
            }
            Button("取消", role: .cancel) { newName = "" }
        }
        .alert("在线歌单刷新失败", isPresented: Binding(
            get: { onlineErrorMessage != nil },
            set: { if !$0 { onlineErrorMessage = nil } }
        )) {
            Button("确定", role: .cancel) { onlineErrorMessage = nil }
        } message: {
            Text(onlineErrorMessage ?? "")
        }
    }

    @ViewBuilder
    private func sectionView(_ section: PlaylistSection) -> some View {
        switch section {
        case .netease: onlinePlaylistsSection
        case .qq: qqPlaylistsSection
        case .local: localPlaylistsSection
        }
    }

    private var onlinePlaylistsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("网易云音乐")
                    .font(.title3.weight(.bold))
                Spacer()
                if account.isLoggedIn {
                    Button {
                        Task {
                            await refreshOnlinePlaylists()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }

            if !account.isLoggedIn {
                VStack(spacing: 10) {
                    Text("登录后查看和管理网易云个人歌单")
                        .foregroundStyle(.secondary)
                    Button("网页登录网易云音乐") { showNeteaseWebLogin = true }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
                .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
            } else if account.userPlaylists.isEmpty {
                Text("暂无在线歌单")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(account.userPlaylists) { playlist in
                        NavigationLink(value: Destination.playlist(playlist.id)) {
                            playlistRow(playlist)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Layout.contentInset)
    }

    private var localPlaylistsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("本地歌单")
                .font(.title3.weight(.bold))

            if store.playlists.isEmpty {
                VStack(spacing: 14) {
                    EmptyStateView(
                        icon: "music.note.list",
                        title: "还没有本地歌单",
                        subtitle: "可以导入其他音乐软件的歌单，或在歌曲页面点“加入歌单”"
                    )
                    Button {
                        showImport = true
                    } label: {
                        Label("导入歌单", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 44)
                }
                .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(store.playlists) { playlist in
                        NavigationLink(value: Destination.localPlaylist(playlist.id)) {
                            playlistRow(playlist)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            ShareLink(item: store.exportText(playlist)) {
                                Label("导出歌单", systemImage: "square.and.arrow.up")
                            }
                            Button("删除歌单", role: .destructive) {
                                store.delete(id: playlist.id)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                store.delete(id: playlist.id)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Layout.contentInset)
    }

    private var qqPlaylistsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("QQ音乐")
                    .font(.title3.weight(.bold))
                Spacer()
                if qqMusic.isLoggedIn {
                    Button {
                        Task { await refreshQQPlaylists() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            if !qqMusic.isLoggedIn {
                VStack(spacing: 10) {
                    Text("登录后查看和管理 QQ 音乐个人歌单")
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Button("QQ 音乐登录") { showQQWebLogin = true }
                            .buttonStyle(.borderedProminent)
                        Button("手动导入 Cookie") { showQQLogin = true }
                            .buttonStyle(.bordered)
                    }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
                .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
            } else if qqMusic.playlists.isEmpty {
                Text("暂无 QQ 音乐在线歌单")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(qqMusic.playlists) { playlist in
                        NavigationLink(value: Destination.qqPlaylist(playlist)) {
                            playlistRow(playlist)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Layout.contentInset)
        .task {
            if qqMusic.isLoggedIn {
                await refreshQQPlaylists()
            }
        }
        .sheet(isPresented: $showQQLogin) { QQCookieSheet() }
        .sheet(isPresented: $showQQWebLogin) { QQLoginSheet() }
        .sheet(isPresented: $showNeteaseWebLogin) { NeteaseWebLoginSheet() }
    }

    private func refreshOnlinePlaylists() async {
        do {
            try await account.refreshLibraryThrowing()
            try Task.checkCancellation()
            guard qqMusic.isLoggedIn else { return }
            try await qqMusic.refreshPlaylists()
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            onlineErrorMessage = error.localizedDescription
        }
    }

    private func refreshQQPlaylists() async {
        do {
            try Task.checkCancellation()
            try await qqMusic.refreshPlaylists()
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            onlineErrorMessage = error.localizedDescription
        }
    }

    private func playlistRow(_ playlist: LocalPlaylist) -> some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: playlist.coverURL?.resizedImageURL(160), animated: false)
                .frame(width: 68, height: 68)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    if playlist.coverURL == nil {
                        Image(systemName: "music.note.list")
                            .font(.title2)
                            .foregroundStyle(Theme.accent)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(playlist.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(["\(playlist.tracks.count) 首", playlist.sourceName]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
    }

    private func playlistRow(_ playlist: PlaylistSummary) -> some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: playlist.coverURL?.resizedImageURL(160), animated: false)
                .frame(width: 68, height: 68)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(playlist.name)
                    .font(.headline)
                    .lineLimit(2)
                Text("\(playlist.trackCount) 首")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
    }

    private func playlistRow(_ playlist: QQMusicAPI.Playlist) -> some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: playlist.coverURL?.resizedImageURL(160), animated: false)
                .frame(width: 68, height: 68)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(playlist.name).font(.headline).lineLimit(2)
                Text("\(playlist.trackCount) 首").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
    }
}

private struct PlaylistSectionDropDelegate: DropDelegate {
    let target: PlaylistSection
    @Binding var order: [PlaylistSection]
    @Binding var isEnabled: Bool

    func dropEntered(info: DropInfo) {
        guard isEnabled,
              let provider = info.itemProviders(for: [.text]).first,
              let targetIndex = order.firstIndex(of: target) else { return }

        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let value = object as? NSString,
                  let source = PlaylistSection(rawValue: value as String),
                  source != target else { return }
            DispatchQueue.main.async {
                guard let sourceIndex = order.firstIndex(of: source), sourceIndex != targetIndex else { return }
                withAnimation(AppAnimation.quick) {
                    order.move(
                        fromOffsets: IndexSet(integer: sourceIndex),
                        toOffset: targetIndex + (sourceIndex < targetIndex ? 1 : 0)
                    )
                }
                PlaylistSectionOrder.save(order)
            }
        }
    }

    func performDrop(info: DropInfo) {
        PlaylistSectionOrder.save(order)
    }
}

private struct QQCookieSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var qqMusic = QQMusicAPI.shared
    @State private var cookie = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("QQ 音乐 Cookie") {
                    SecureField("粘贴 Cookie", text: $cookie)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    Button {
                        isSaving = true
                        qqMusic.setCookie(cookie)
                        Task {
                            do {
                                try await qqMusic.refreshPlaylists()
                                isSaving = false
                                dismiss()
                            } catch {
                                isSaving = false
                                errorMessage = error.localizedDescription
                            }
                        }
                    } label: {
                        HStack {
                            Text(isSaving ? "正在验证…" : "保存并验证")
                            Spacer()
                            if isSaving { ProgressView() }
                        }
                    }
                    .disabled(isSaving || cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("退出 QQ 音乐", role: .destructive) {
                        qqMusic.logout()
                        dismiss()
                    }
                }
                Section("安全说明") {
                    Text("Cookie 仅保存在本机 Keychain，用于访问你的 QQ 音乐歌单。不要把 Cookie 分享给他人。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("QQ 音乐账号")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
            .alert("验证失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("确定", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }
}

struct ImportPlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = LocalPlaylistStore.shared
    @State private var input = ""
    @State private var isImporting = false
    @State private var showFileImporter = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("粘贴歌单") {
                    TextEditor(text: $input)
                        .frame(minHeight: 180)
                        .font(.body)
                        .overlay(alignment: .topLeading) {
                            if input.isEmpty {
                                Text("粘贴网易云公开歌单链接，或粘贴其他音乐软件导出的歌单 JSON。网易云歌曲仍由已选 LX 音源负责播放。")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                Section {
                    Button {
                        showFileImporter = true
                    } label: {
                        Label("选择 JSON / 文本文件", systemImage: "doc.badge.plus")
                    }
                    .frame(minHeight: 44)
                    Button {
                        importPlaylist()
                    } label: {
                        HStack {
                            Text(isImporting ? "正在导入…" : "开始导入")
                            Spacer()
                            if isImporting { ProgressView() }
                        }
                    }
                    .disabled(isImporting || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .frame(minHeight: 44)
                }

                Section("说明") {
                    Text("歌单只保存到本机，不会修改原音乐软件。支持网易云公开歌单链接和 JSON；在线目录只读取公开信息，实际播放仍使用你自己添加的 LX 音源。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("导入歌单")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.json, .plainText],
                allowsMultipleSelection: false
            ) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                do {
                    input = try String(contentsOf: url, encoding: .utf8)
                } catch {
                    errorMessage = "读取文件失败：\(error.localizedDescription)"
                }
            }
            .alert("导入失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("确定", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }

    private func importPlaylist() {
        isImporting = true
        Task {
            do {
                _ = try await store.importPlaylist(from: input)
                isImporting = false
                dismiss()
            } catch {
                isImporting = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct LocalPlaylistDetailView: View {
    let playlistID: UUID

    @StateObject private var store = LocalPlaylistStore.shared
    @EnvironmentObject private var player: PlayerService
    @State private var showRename = false
    @State private var renameText = ""

    var body: some View {
        ScrollView {
            if let playlist = store.playlist(id: playlistID) {
                VStack(alignment: .leading, spacing: 18) {
                    header(playlist)

                    HStack(spacing: 10) {
                        Button {
                            player.play(tracks: playlist.tracks, source: .none)
                        } label: {
                            Label("播放全部", systemImage: "play.fill")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(playlist.tracks.isEmpty)

                        ShareLink(item: store.exportText(playlist)) {
                            Image(systemName: "square.and.arrow.up")
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("导出歌单")
                    }
                    .padding(.horizontal, Theme.Layout.contentInset)

                    if playlist.tracks.isEmpty {
                        EmptyStateView(icon: "music.note.list", title: "歌单暂无歌曲")
                            .frame(minHeight: 260)
                    } else {
                        TrackListView(
                            tracks: playlist.tracks,
                            source: .none,
                            onRemoved: { track in
                                store.remove(track, from: playlistID)
                            }
                        )
                        .padding(.horizontal, Theme.Layout.contentInset - 10)
                    }
                }
                .padding(.vertical, Theme.Layout.contentInset)
            } else {
                ErrorStateView(message: "歌单不存在") {}
                    .frame(minHeight: 360)
            }
            PlayerClearanceSpacer()
        }
        .navigationTitle(store.playlist(id: playlistID)?.name ?? "歌单")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    renameText = store.playlist(id: playlistID)?.name ?? ""
                    showRename = true
                } label: {
                    Label("重命名", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    store.delete(id: playlistID)
                } label: {
                    Label("删除歌单", systemImage: "trash")
                }
            }
        }
        .alert("重命名歌单", isPresented: $showRename) {
            TextField("歌单名称", text: $renameText)
            Button("保存") { store.rename(id: playlistID, name: renameText) }
            Button("取消", role: .cancel) {}
        }
    }

    private func header(_ playlist: LocalPlaylist) -> some View {
        HStack(alignment: .top, spacing: 14) {
            CachedAsyncImage(url: playlist.coverURL?.resizedImageURL(384))
                .frame(width: 126, height: 126)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    if playlist.coverURL == nil {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(Theme.accent)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 7) {
                Text(playlist.name)
                    .font(.title3.weight(.bold))
                    .lineLimit(3)
                if let sourceName = playlist.sourceName, !sourceName.isEmpty {
                    Text("来源：\(sourceName)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text("\(playlist.tracks.count) 首")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Layout.contentInset)
    }
}

struct QQPlaylistDetailView: View {
    let playlist: QQMusicAPI.Playlist
    @StateObject private var qqMusic = QQMusicAPI.shared
    @State private var tracks: [Track] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @EnvironmentObject private var player: PlayerService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(playlist.name).font(.title3.weight(.bold))
                        Text("QQ 音乐 · \(tracks.count) 首").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        player.play(tracks: tracks, source: .playlist(playlist.id), context: .playlist(id: playlist.id, name: playlist.name))
                    } label: {
                        Image(systemName: "play.fill").frame(width: 40, height: 40)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(tracks.isEmpty)
                }
                .padding(.horizontal, Theme.Layout.contentInset)

                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 260)
                } else if let errorMessage {
                    ErrorStateView(message: errorMessage) { Task { await load() } }
                        .frame(minHeight: 260)
                } else if tracks.isEmpty {
                    EmptyStateView(
                        icon: "music.note.list",
                        title: "歌单还是空的",
                        subtitle: "可以在歌曲菜单中选择“收藏到歌单”添加歌曲"
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
                } else {
                    TrackListView(
                        tracks: tracks,
                        source: .playlist(playlist.id),
                        context: .playlist(id: playlist.id, name: playlist.name),
                        onRemoved: { track in
                            Task {
                                guard let index = tracks.firstIndex(where: { $0.playbackKey == track.playbackKey }) else { return }
                                do {
                                    try await qqMusic.remove(track, from: playlist)
                                    tracks.remove(at: index)
                                } catch { errorMessage = error.localizedDescription }
                            }
                        }
                    )
                    .padding(.horizontal, Theme.Layout.contentInset - 10)
                }
                PlayerClearanceSpacer()
            }
            .padding(.vertical, 14)
        }
        .navigationTitle(playlist.name)
        .task { await load() }
    }

    private func load() async {
        isLoading = tracks.isEmpty
        do {
            tracks = try await qqMusic.detail(playlist).tracks
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }
}
