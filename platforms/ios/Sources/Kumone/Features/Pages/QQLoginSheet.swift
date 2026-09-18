import SwiftUI

#if os(iOS)
import WebKit

struct QQLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var qqMusic = QQMusicAPI.shared
    @State private var webView: WKWebView?
    @State private var isReadingCookies = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                QQWebView { webView = $0 }
                Button {
                    readCookies()
                } label: {
                    HStack {
                        Text(isReadingCookies ? "正在读取登录状态…" : "登录完成后读取 Cookie")
                        Spacer()
                        if isReadingCookies { ProgressView() }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isReadingCookies)
                .padding(16)
            }
            .navigationTitle("QQ 音乐登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .alert("QQ 音乐登录", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("确定", role: .cancel) { message = nil }
            } message: { Text(message ?? "") }
        }
    }

    private func readCookies() {
        guard let webView else { return }
        isReadingCookies = true
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            let raw = cookies
                .filter { $0.domain.contains("qq.com") }
                .map { "\($0.name)=\($0.value)" }
                .joined(separator: "; ")
            DispatchQueue.main.async {
                isReadingCookies = false
                guard !raw.isEmpty else {
                    message = "没有读取到 QQ 音乐登录状态，请先完成登录。"
                    return
                }
                qqMusic.setCookie(raw)
                Task {
                    do {
                        try await qqMusic.refreshPlaylists()
                        dismiss()
                    } catch {
                        message = error.localizedDescription
                    }
                }
            }
        }
    }
}

private struct QQWebView: UIViewRepresentable {
    let onReady: (WKWebView) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: configuration)

        // QQ Music serves a mobile login page to iPhone user agents.  That
        // page expects the QQ Music app to pull the login state and does not
        // expose the desktop QR flow.  Use a desktop Safari user agent so the
        // web login presents the computer-style QR code instead.
        view.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"
        view.load(URLRequest(url: URL(string: "https://y.qq.com/n/ryqq/login")!))
        DispatchQueue.main.async { onReady(view) }
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#else

struct QQLoginSheet: View {
    var body: some View {
        Text("QQ 音乐网页登录仅支持 iOS")
    }
}
#endif
