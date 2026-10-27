import UIKit
import WebKit

/// 用 WKWebView 把 `fitness-app` 那套网页原样装进来。
/// 网页代码一行没改：改完网页 → 重新跑流水线 → 出的 IPA 就是新版。
final class WebViewController: UIViewController {

    private var webView: WKWebView!

    override func viewDidLoad() {
        super.viewDidLoad()

        let bg = UIColor(red: 13 / 255, green: 13 / 255, blue: 20 / 255, alpha: 1)   // #0D0D14
        view.backgroundColor = bg

        let conf = WKWebViewConfiguration()
        conf.allowsInlineMediaPlayback = true
        conf.mediaTypesRequiringUserActionForPlayback = []   // 允许静音保活音轨自动起播
        conf.websiteDataStore = .default()                    // 持久化存储，别用 nonPersistent
        conf.defaultWebpagePreferences.allowsContentJavaScript = true

        let wv = WKWebView(frame: view.bounds, configuration: conf)
        wv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.isOpaque = false
        wv.backgroundColor = bg
        wv.scrollView.backgroundColor = bg
        wv.scrollView.contentInsetAdjustmentBehavior = .never   // 安全区交给 CSS 的 env()
        wv.scrollView.bounces = false
        wv.scrollView.showsVerticalScrollIndicator = false
        wv.allowsBackForwardNavigationGestures = false
        wv.allowsLinkPreview = false
        if #available(iOS 16.4, *) {
            wv.isInspectable = true   // 想调试：Mac/Safari 连上后可直接检查
        }
        view.addSubview(wv)
        webView = wv

        loadApp()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    private func loadApp() {
        let port: UInt16 = 8787

        if LocalWebServer.shared.start(port: port),
           let url = URL(string: "http://127.0.0.1:\(port)/index.html") {
            var req = URLRequest(url: url)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            req.timeoutInterval = 15
            webView.load(req)
            return
        }

        // 兜底：本地服务起不来就直接读文件（存储可能不持久，但界面能用）
        if let f = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Web") {
            NSLog("[REPS] fallback to file://")
            webView.loadFileURL(f, allowingReadAccessTo: f.deletingLastPathComponent())
        } else {
            webView.loadHTMLString(errorHTML("Web 资源缺失：打包时没把 fitness-app 的文件拷进 Web 目录。"), baseURL: nil)
        }
    }

    private func errorHTML(_ msg: String) -> String {
        """
        <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
        <body style="margin:0;background:#0D0D14;color:#FFF1E8;font-family:-apple-system;
                     padding:76px 24px;line-height:1.7">
          <div style="font-size:12px;letter-spacing:.16em;color:#8C8CA8">REPS</div>
          <h2 style="font-size:22px;margin:10px 0 14px">加载失败</h2>
          <p style="color:#8C8CA8;font-size:14px">\(msg)</p>
        </body>
        """
    }
}

// MARK: - 导航

extension WebViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        NSLog("[REPS] load failed: \(error)")
        if webView.url == nil,
           let f = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Web") {
            webView.loadFileURL(f, allowingReadAccessTo: f.deletingLastPathComponent())
        }
    }
}

// MARK: - 网页弹窗 & 外链
// 注意：「结束训练」按钮用的是 confirm()，不实现这个代理，点了会毫无反应。

extension WebViewController: WKUIDelegate {

    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
            completionHandler(alert.textFields?.first?.text)
        })
        present(alert, animated: true)
    }

    /// target=_blank / 外链，用系统浏览器打开，别在 App 里跳走
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            UIApplication.shared.open(url)
        }
        return nil
    }
}
