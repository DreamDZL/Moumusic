import SwiftUI

#if os(iOS)
import WebKit

/// Desktop NetEase web login.  Unlike the native QR flow, this keeps the QR
/// code in the sheet and lets the user scan it from any device/browser.
struct NeteaseWebLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var account: AccountStore
    @State private var webView: WKWebView?
    @State private var isReadingCookies = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                NeteaseWebView { webView = $0 }
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
            .navigationTitle("网易云音乐网页登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .alert("网易云音乐登录", isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )) {
                Button("确定", role: .cancel) { message = nil }
            } message: {
                Text(message ?? "")
            }
        }
    }

    private func readCookies() {
        guard let webView else { return }
        isReadingCookies = true
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            let relevant = cookies.filter {
                $0.domain.contains("163.com") || $0.domain.contains("netease.com")
            }
            let values = relevant.reduce(into: [String: String]()) { result, cookie in
                result[cookie.name] = cookie.value
            }
            DispatchQueue.main.async {
                guard values["MUSIC_U"] != nil else {
                    isReadingCookies = false
                    message = "没有读取到网易云登录状态，请先在网页中完成扫码或账号登录。"
                    return
                }
                NeteaseClient.shared.setCookies(values)
                Task {
                    await account.bootstrap()
                    isReadingCookies = false
                    if account.isLoggedIn {
                        ToastCenter.shared.show(String(localized: "登录成功！"))
                        dismiss()
                    } else {
                        message = "已读取 Cookie，但账号验证失败，请重新登录。"
                    }
                }
            }
        }
    }
}

private struct NeteaseWebView: UIViewRepresentable {
    let onReady: (WKWebView) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"
        view.load(URLRequest(url: URL(string: "https://music.163.com/#/login")!))
        DispatchQueue.main.async { onReady(view) }
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#else

struct NeteaseWebLoginSheet: View {
    var body: some View { Text("网易云音乐网页登录仅支持 iOS") }
}
#endif
