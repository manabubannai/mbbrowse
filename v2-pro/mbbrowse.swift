// mbブラウザ v1 (classic) — Brave自作版
// WKWebView ベースのプライバシー重視ミニブラウザ。Xcode不要 / 依存ゼロ。
// Shields = 広告・トラッカー遮断(WKContentRuleList)、プライベートウィンドウ、タブ。
import AppKit
import WebKit

// MARK: - 遮断ルール(Shields)
// 代表的な広告/トラッカーのドメインをブロック。WebKit標準のContentRuleListだけで完結。
enum Blocklist {
    static let domains = [
        "doubleclick.net", "googlesyndication.com", "googleadservices.com",
        "google-analytics.com", "googletagmanager.com", "googletagservices.com",
        "adservice.google.com", "pagead2.googlesyndication.com",
        "facebook.net", "connect.facebook.net", "ads-twitter.com", "analytics.twitter.com",
        "amazon-adsystem.com", "adnxs.com", "criteo.com", "criteo.net",
        "scorecardresearch.com", "quantserve.com", "outbrain.com", "taboola.com",
        "moatads.com", "adsrvr.org", "rubiconproject.com", "pubmatic.com",
        "openx.net", "casalemedia.com", "yieldmo.com", "bidswitch.net",
        "hotjar.com", "mouseflow.com", "fullstory.com", "mixpanel.com",
        "segment.io", "segment.com", "branch.io", "appsflyer.com",
        "adform.net", "smartadserver.com", "teads.tv", "sharethis.com",
        "addthis.com", "chartbeat.com", "newrelic.com", "nr-data.net",
        "yandex.ru", "mc.yandex.ru", "advertising.com", "adcolony.com",
    ]

    // WKContentRuleList 用の JSON を生成
    static func json() -> String {
        let rules = domains.map { d -> String in
            """
            {"trigger":{"url-filter":".*","if-domain":["*\(d)"]},"action":{"type":"block"}}
            """
        }
        return "[" + rules.joined(separator: ",") + "]"
    }
}

// MARK: - タブ
final class Tab {
    let webView: WKWebView
    var blockedCount = 0
    init(webView: WKWebView) { self.webView = webView }
}

// MARK: - ウィンドウ(1ウィンドウ=1ブラウザ)
final class BrowserWindowController: NSWindowController, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate, NSTextFieldDelegate {

    let isPrivate: Bool
    var tabs: [Tab] = []
    var current: Tab? { tabs.indices.contains(currentIndex) ? tabs[currentIndex] : nil }
    var currentIndex = 0

    // UI
    let container = NSView()
    let toolbar = NSView()
    let tabBar = NSStackView()
    let backBtn = NSButton()
    let fwdBtn = NSButton()
    let reloadBtn = NSButton()
    let shieldBtn = NSButton()
    let urlField = NSTextField()
    let newTabBtn = NSButton()
    let starBtn = NSButton()
    let webHost = NSView()
    let bookmarkBar = NSStackView()
    let findField = NSTextField()
    var shieldsOn = true
    var ruleList: WKContentRuleList?

    // ブックマーク(永続化 / プライベートウィンドウでは追加しない)
    struct Bookmark: Codable { let title: String; let url: String }
    static func loadBookmarks() -> [Bookmark] {
        guard let d = UserDefaults.standard.data(forKey: "mbbrowse.bookmarks"),
              let b = try? JSONDecoder().decode([Bookmark].self, from: d) else { return [] }
        return b
    }
    static func saveBookmarks(_ b: [Bookmark]) {
        if let d = try? JSONEncoder().encode(b) {
            UserDefaults.standard.set(d, forKey: "mbbrowse.bookmarks")
        }
    }

    // Brave風カラー
    static let bg = NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.14, alpha: 1)
    static let bar = NSColor(calibratedRed: 0.17, green: 0.17, blue: 0.20, alpha: 1)
    static let accent = NSColor(calibratedRed: 0.98, green: 0.29, blue: 0.15, alpha: 1) // Braveオレンジ系
    static let text = NSColor(calibratedWhite: 0.92, alpha: 1)

    init(isPrivate: Bool) {
        self.isPrivate = isPrivate
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        win.title = isPrivate ? "mbブラウザ — プライベート" : "mbブラウザ"
        win.titlebarAppearsTransparent = true
        win.appearance = NSAppearance(named: .darkAqua)
        win.backgroundColor = BrowserWindowController.bg
        win.center()
        super.init(window: win)
        win.delegate = self
        buildUI()
        loadRules { [weak self] in
            self?.addTab(url: URL(string: "https://duckduckgo.com/")!)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: UI構築
    func buildUI() {
        guard let win = window else { return }
        container.frame = win.contentView!.bounds
        container.autoresizingMask = [.width, .height]
        win.contentView = container

        toolbar.wantsLayer = true
        toolbar.layer?.backgroundColor = BrowserWindowController.bar.cgColor
        container.addSubview(toolbar)

        tabBar.orientation = .horizontal
        tabBar.spacing = 4
        tabBar.alignment = .centerY
        container.addSubview(tabBar)

        func mkBtn(_ title: String, _ sel: Selector) -> NSButton {
            let b = NSButton(title: title, target: self, action: sel)
            b.bezelStyle = .regularSquare
            b.isBordered = false
            b.font = NSFont.systemFont(ofSize: 16)
            b.contentTintColor = BrowserWindowController.text
            b.wantsLayer = true
            return b
        }
        backBtn.title = "‹"; backBtn.target = self; backBtn.action = #selector(goBack)
        fwdBtn.title = "›"; fwdBtn.target = self; fwdBtn.action = #selector(goForward)
        reloadBtn.title = "⟳"; reloadBtn.target = self; reloadBtn.action = #selector(reload)
        for b in [backBtn, fwdBtn, reloadBtn] {
            b.bezelStyle = .regularSquare; b.isBordered = false
            b.font = NSFont.systemFont(ofSize: 20)
            b.contentTintColor = BrowserWindowController.text
            toolbar.addSubview(b)
        }

        // Shieldsボタン(ライオン=Braveのシールド相当)
        shieldBtn.title = "🦁"
        shieldBtn.bezelStyle = .regularSquare; shieldBtn.isBordered = false
        shieldBtn.font = NSFont.systemFont(ofSize: 17)
        shieldBtn.target = self; shieldBtn.action = #selector(toggleShields)
        shieldBtn.toolTip = "Shields: 広告・トラッカー遮断のオン/オフ"
        toolbar.addSubview(shieldBtn)

        urlField.placeholderString = "検索または URL を入力"
        urlField.font = NSFont.systemFont(ofSize: 13)
        urlField.textColor = BrowserWindowController.text
        urlField.backgroundColor = BrowserWindowController.bg
        urlField.wantsLayer = true
        urlField.layer?.cornerRadius = 8
        urlField.isBezeled = false
        urlField.focusRingType = .none
        urlField.delegate = self
        urlField.target = self
        urlField.action = #selector(navigateFromField)
        urlField.usesSingleLineMode = true
        let cell = urlField.cell as? NSTextFieldCell
        cell?.usesSingleLineMode = true
        toolbar.addSubview(urlField)

        newTabBtn.title = "＋"; newTabBtn.bezelStyle = .regularSquare; newTabBtn.isBordered = false
        newTabBtn.font = NSFont.systemFont(ofSize: 18)
        newTabBtn.contentTintColor = BrowserWindowController.text
        newTabBtn.target = self; newTabBtn.action = #selector(newTabAction)
        toolbar.addSubview(newTabBtn)

        starBtn.title = "☆"
        starBtn.bezelStyle = .regularSquare; starBtn.isBordered = false
        starBtn.font = NSFont.systemFont(ofSize: 17)
        starBtn.contentTintColor = BrowserWindowController.text
        starBtn.target = self; starBtn.action = #selector(toggleBookmark)
        starBtn.toolTip = "このページをブックマーク"
        toolbar.addSubview(starBtn)

        // ブックマークバー
        bookmarkBar.orientation = .horizontal
        bookmarkBar.spacing = 4
        bookmarkBar.alignment = .centerY
        bookmarkBar.wantsLayer = true
        bookmarkBar.layer?.backgroundColor = BrowserWindowController.bg.cgColor
        container.addSubview(bookmarkBar)

        // ページ内検索フィールド(⌘F)
        findField.placeholderString = "ページ内を検索…"
        findField.font = NSFont.systemFont(ofSize: 12)
        findField.textColor = BrowserWindowController.text
        findField.backgroundColor = BrowserWindowController.bar
        findField.wantsLayer = true
        findField.layer?.cornerRadius = 6
        findField.isBezeled = false
        findField.focusRingType = .none
        findField.isHidden = true
        findField.target = self
        findField.action = #selector(performFind)
        container.addSubview(findField)

        refreshBookmarkBar()

        webHost.wantsLayer = true
        webHost.layer?.backgroundColor = NSColor.white.cgColor
        container.addSubview(webHost)

        layout()
    }

    func layout() {
        let b = container.bounds
        let tabH: CGFloat = 36, barH: CGFloat = 44, bmH: CGFloat = 30
        tabBar.frame = NSRect(x: 12, y: b.height - tabH, width: b.width - 60, height: tabH)
        newTabBtn.frame = NSRect(x: b.width - 44, y: b.height - tabH, width: 32, height: tabH)
        toolbar.frame = NSRect(x: 0, y: b.height - tabH - barH, width: b.width, height: barH)
        let y: CGFloat = 6
        backBtn.frame = NSRect(x: 8, y: y, width: 30, height: 32)
        fwdBtn.frame = NSRect(x: 40, y: y, width: 30, height: 32)
        reloadBtn.frame = NSRect(x: 72, y: y, width: 30, height: 32)
        shieldBtn.frame = NSRect(x: 108, y: y, width: 30, height: 32)
        urlField.frame = NSRect(x: 146, y: y + 3, width: b.width - 198, height: 26)
        starBtn.frame = NSRect(x: b.width - 44, y: y, width: 32, height: 32)
        bookmarkBar.frame = NSRect(x: 12, y: b.height - tabH - barH - bmH, width: b.width - 24, height: bmH)
        findField.frame = NSRect(x: b.width - 272, y: b.height - tabH - barH - bmH - 40, width: 260, height: 30)
        webHost.frame = NSRect(x: 0, y: 0, width: b.width, height: b.height - tabH - barH - bmH)
    }

    func windowDidResize(_ n: Notification) { layout(); refreshTabBar() }

    // MARK: ルール読み込み
    func loadRules(_ done: @escaping () -> Void) {
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "mbbrowse-shields", encodedContentRuleList: Blocklist.json()
        ) { [weak self] list, err in
            if let err = err { NSLog("rule compile error: \(err)") }
            self?.ruleList = list
            done()
        }
    }

    // MARK: タブ操作
    func makeWebView() -> WKWebView {
        let cfg = WKWebViewConfiguration()
        if isPrivate {
            cfg.websiteDataStore = .nonPersistent()
        }
        let ucc = WKUserContentController()
        if shieldsOn, let rl = ruleList { ucc.add(rl) }
        cfg.userContentController = ucc
        let wv = WKWebView(frame: webHost.bounds, configuration: cfg)
        wv.autoresizingMask = [.width, .height]
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.allowsBackForwardNavigationGestures = true
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        return wv
    }

    @discardableResult
    func addTab(url: URL?) -> Tab {
        let tab = Tab(webView: makeWebView())
        tabs.append(tab)
        currentIndex = tabs.count - 1
        showCurrent()
        if let url = url { tab.webView.load(URLRequest(url: url)) }
        refreshTabBar()
        return tab
    }

    func showCurrent() {
        webHost.subviews.forEach { $0.removeFromSuperview() }
        if let wv = current?.webView {
            wv.frame = webHost.bounds
            webHost.addSubview(wv)
            window?.makeFirstResponder(wv)
            syncURLField()
        }
    }

    func selectTab(_ i: Int) {
        guard tabs.indices.contains(i) else { return }
        currentIndex = i; showCurrent(); refreshTabBar()
    }

    func closeTab(_ i: Int) {
        guard tabs.indices.contains(i) else { return }
        tabs[i].webView.removeFromSuperview()
        tabs.remove(at: i)
        if tabs.isEmpty { window?.close(); return }
        currentIndex = min(currentIndex, tabs.count - 1)
        showCurrent(); refreshTabBar()
    }

    func refreshTabBar() {
        tabBar.arrangedSubviews.forEach { tabBar.removeArrangedSubview($0); $0.removeFromSuperview() }
        for (i, tab) in tabs.enumerated() {
            let title = tab.webView.title?.isEmpty == false ? tab.webView.title! : "新しいタブ"
            let short = String(title.prefix(18))
            let btn = NSButton(title: short, target: self, action: #selector(tabClicked(_:)))
            btn.tag = i
            btn.bezelStyle = .regularSquare
            btn.isBordered = false
            btn.font = NSFont.systemFont(ofSize: 12)
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 7
            btn.layer?.backgroundColor = (i == currentIndex ? BrowserWindowController.accent.withAlphaComponent(0.85) : BrowserWindowController.bg).cgColor
            btn.contentTintColor = BrowserWindowController.text
            btn.widthAnchor.constraint(equalToConstant: 150).isActive = true
            btn.heightAnchor.constraint(equalToConstant: 28).isActive = true
            tabBar.addArrangedSubview(btn)
        }
    }

    @objc func tabClicked(_ s: NSButton) { selectTab(s.tag) }

    // MARK: アクション
    @objc func goBack() { current?.webView.goBack() }
    @objc func goForward() { current?.webView.goForward() }
    @objc func reload() { current?.webView.reload() }
    @objc func newTabAction() { addTab(url: URL(string: "https://duckduckgo.com/")!) }

    @objc func toggleShields() {
        shieldsOn.toggle()
        shieldBtn.alphaValue = shieldsOn ? 1.0 : 0.4
        // 全タブに反映(現タブのみ再読込)
        for tab in tabs {
            let ucc = tab.webView.configuration.userContentController
            ucc.removeAllContentRuleLists()
            if shieldsOn, let rl = ruleList { ucc.add(rl) }
        }
        current?.webView.reload()
    }

    @objc func navigateFromField() {
        let raw = urlField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }
        let url: URL
        if raw.contains(".") && !raw.contains(" ") {
            url = URL(string: raw.hasPrefix("http") ? raw : "https://\(raw)")
                ?? searchURL(raw)
        } else {
            url = searchURL(raw)
        }
        if current == nil { addTab(url: url) } else { current?.webView.load(URLRequest(url: url)) }
    }

    func searchURL(_ q: String) -> URL {
        let e = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        return URL(string: "https://duckduckgo.com/?q=\(e)")!
    }

    func syncURLField() {
        if let u = current?.webView.url?.absoluteString { urlField.stringValue = u }
        updateStar()
    }

    func updateStar() {
        let url = current?.webView.url?.absoluteString ?? ""
        let marked = BrowserWindowController.loadBookmarks().contains { $0.url == url }
        starBtn.title = marked ? "★" : "☆"
        starBtn.contentTintColor = marked ? BrowserWindowController.accent : BrowserWindowController.text
    }

    @objc func toggleBookmark() {
        guard let url = current?.webView.url?.absoluteString, !url.isEmpty else { return }
        var bms = BrowserWindowController.loadBookmarks()
        if let i = bms.firstIndex(where: { $0.url == url }) {
            bms.remove(at: i)
        } else {
            let title = current?.webView.title?.isEmpty == false ? current!.webView.title! : url
            bms.append(Bookmark(title: title, url: url))
        }
        BrowserWindowController.saveBookmarks(bms)
        updateStar(); refreshBookmarkBar()
    }

    func refreshBookmarkBar() {
        bookmarkBar.arrangedSubviews.forEach { bookmarkBar.removeArrangedSubview($0); $0.removeFromSuperview() }
        for (i, bm) in BrowserWindowController.loadBookmarks().enumerated() {
            let btn = NSButton(title: String(bm.title.prefix(16)), target: self, action: #selector(openBookmark(_:)))
            btn.tag = i
            btn.bezelStyle = .regularSquare; btn.isBordered = false
            btn.font = NSFont.systemFont(ofSize: 11)
            btn.contentTintColor = BrowserWindowController.text
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 6
            btn.layer?.backgroundColor = BrowserWindowController.bar.cgColor
            btn.heightAnchor.constraint(equalToConstant: 22).isActive = true
            bookmarkBar.addArrangedSubview(btn)
        }
    }

    @objc func openBookmark(_ s: NSButton) {
        let bms = BrowserWindowController.loadBookmarks()
        guard bms.indices.contains(s.tag), let url = URL(string: bms[s.tag].url) else { return }
        if current == nil { addTab(url: url) } else { current?.webView.load(URLRequest(url: url)) }
    }

    @objc func showFind() {
        findField.isHidden = false
        window?.makeFirstResponder(findField)
    }

    @objc func performFind() {
        let q = findField.stringValue
        guard !q.isEmpty, let wv = current?.webView else { findField.isHidden = true; return }
        let cfg = WKFindConfiguration()
        cfg.caseSensitive = false
        wv.find(q, configuration: cfg) { _ in }
    }

    // MARK: WKNavigationDelegate
    func webView(_ wv: WKWebView, didFinish nav: WKNavigation!) {
        syncURLField(); refreshTabBar()
    }
    func webView(_ wv: WKWebView, didCommit nav: WKNavigation!) { syncURLField() }

    // 新規ウィンドウ要求(target=_blank)は新タブで開く
    func webView(_ wv: WKWebView, createWebViewWith cfg: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url { addTab(url: url) }
        return nil
    }
}

// MARK: - App
final class AppDelegate: NSObject, NSApplicationDelegate {
    var windows: [BrowserWindowController] = []

    func applicationDidFinishLaunching(_ n: Notification) {
        setupMenu()
        openWindow(isPrivate: false)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }

    func openWindow(isPrivate: Bool) {
        let wc = BrowserWindowController(isPrivate: isPrivate)
        windows.append(wc)
        wc.showWindow(nil)
    }

    @objc func newWindow() { openWindow(isPrivate: false) }
    @objc func newPrivateWindow() { openWindow(isPrivate: true) }
    @objc func newTab() { (NSApp.keyWindow?.windowController as? BrowserWindowController)?.newTabAction() }
    @objc func closeTab() {
        if let wc = NSApp.keyWindow?.windowController as? BrowserWindowController {
            wc.closeTab(wc.currentIndex)
        }
    }
    @objc func focusURL() {
        (NSApp.keyWindow?.windowController as? BrowserWindowController)?.window?.makeFirstResponder(
            (NSApp.keyWindow?.windowController as? BrowserWindowController)?.urlField)
    }
    @objc func showFind() {
        (NSApp.keyWindow?.windowController as? BrowserWindowController)?.showFind()
    }

    func setupMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "mbブラウザについて", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "mbブラウザを終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let fileItem = NSMenuItem(); main.addItem(fileItem)
        let fileMenu = NSMenu(title: "ファイル")
        fileMenu.addItem(withTitle: "新しいタブ", action: #selector(newTab), keyEquivalent: "t")
        fileMenu.addItem(withTitle: "新しいウィンドウ", action: #selector(newWindow), keyEquivalent: "n")
        let pv = NSMenuItem(title: "新しいプライベートウィンドウ", action: #selector(newPrivateWindow), keyEquivalent: "n")
        pv.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(pv)
        fileMenu.addItem(withTitle: "タブを閉じる", action: #selector(closeTab), keyEquivalent: "w")
        fileItem.submenu = fileMenu

        let editItem = NSMenuItem(); main.addItem(editItem)
        let editMenu = NSMenu(title: "編集")
        editMenu.addItem(withTitle: "取り消す", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "やり直す", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "カット", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "コピー", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "ペースト", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "すべてを選択", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(withTitle: "URLバーへ移動", action: #selector(focusURL), keyEquivalent: "l")
        editMenu.addItem(withTitle: "ページ内を検索", action: #selector(showFind), keyEquivalent: "f")
        editItem.submenu = editMenu

        NSApp.mainMenu = main
    }
}

@main
struct Main {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        app.delegate = delegate
        _ = delegate // 保持
        app.run()
    }
}
