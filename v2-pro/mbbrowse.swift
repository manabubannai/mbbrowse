// Mado Pro v2 — ミニマルな WKWebView ブラウザ。Xcode不要 / 依存ゼロ。
// v1 + ブックマークバー(★で追加・永続化) + ページ内検索(⌘F)。
// テーマ切替(システム/ライト/ダーク)、Chrome拡張サブセット(content_scripts注入)。
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

// MARK: - テーマ
enum ThemeMode: String, CaseIterable {
    case system, light, dark
    static let key = "mado.theme"
    static var current: ThemeMode {
        ThemeMode(rawValue: UserDefaults.standard.string(forKey: key) ?? "system") ?? .system
    }
    static func set(_ m: ThemeMode) {
        UserDefaults.standard.set(m.rawValue, forKey: key)
        apply()
    }
    static func apply() {
        switch current {
        case .system: NSApp.appearance = nil
        case .light:  NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:   NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

// 実効アピアランスに応じた配色(無彩色・ミニマル)
struct Palette {
    let bg: NSColor        // ウィンドウ/スタート画面
    let bar: NSColor       // ツールバー
    let field: NSColor     // URLバー
    let text: NSColor
    let tabActive: NSColor

    static let dark = Palette(
        bg: NSColor(calibratedRed: 0.15, green: 0.16, blue: 0.17, alpha: 1),   // #26282B相当
        bar: NSColor(calibratedRed: 0.19, green: 0.20, blue: 0.21, alpha: 1),
        field: NSColor(calibratedWhite: 0.10, alpha: 1),
        text: NSColor(calibratedWhite: 0.92, alpha: 1),
        tabActive: NSColor(calibratedWhite: 0.34, alpha: 1))
    static let light = Palette(
        bg: NSColor(calibratedWhite: 0.96, alpha: 1),
        bar: NSColor(calibratedWhite: 0.90, alpha: 1),
        field: NSColor(calibratedWhite: 1.0, alpha: 1),
        text: NSColor(calibratedWhite: 0.13, alpha: 1),
        tabActive: NSColor(calibratedWhite: 0.78, alpha: 1))

    static func current(for view: NSView) -> Palette {
        let dark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark ? .dark : .light
    }
}

// 実効アピアランス変化を通知するルートビュー
final class ThemedView: NSView {
    var onAppearanceChange: (() -> Void)?
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }
}

// MARK: - Chrome拡張サブセット(content_scriptsのみ)
// ~/Library/Application Support/Mado/Extensions/ に展開済み(unpacked)拡張を置くと、
// manifest.json(v2/v3)の content_scripts(js/css・matches・run_at)を WKUserScript として注入する。
// background/service worker・chrome.* API 本体は非対応。
final class ExtensionManager {
    static let shared = ExtensionManager()
    private(set) var scripts: [WKUserScript] = []
    private(set) var names: [String] = []

    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mado/Extensions", isDirectory: true)
    }

    func ensureDirectory() {
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
    }

    func reload() {
        ensureDirectory()
        scripts = []; names = []
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: Self.directory, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        for dir in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let manifest = dir.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: manifest),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
            let name = (obj["name"] as? String) ?? dir.lastPathComponent
            guard let contentScripts = obj["content_scripts"] as? [[String: Any]] else {
                names.append("\(name)(content_scriptsなし・スキップ)"); continue
            }
            var injected = 0
            for cs in contentScripts {
                guard let matches = cs["matches"] as? [String], !matches.isEmpty else { continue }
                let patterns = matches.compactMap { Self.regexSource(for: $0) }
                guard !patterns.isEmpty else { continue }
                let excludes = ((cs["exclude_matches"] as? [String]) ?? []).compactMap { Self.regexSource(for: $0) }

                var css = ""
                for f in (cs["css"] as? [String]) ?? [] {
                    if let t = try? String(contentsOf: dir.appendingPathComponent(f), encoding: .utf8) { css += t + "\n" }
                }
                var js = ""
                for f in (cs["js"] as? [String]) ?? [] {
                    if let code = try? String(contentsOf: dir.appendingPathComponent(f), encoding: .utf8) {
                        js += "try{\n\(code)\n}catch(e){console.error('[Mado拡張]', \(Self.jsLiteral(name)), e);}\n"
                    }
                }
                guard !css.isEmpty || !js.isEmpty else { continue }

                let runAt: WKUserScriptInjectionTime = (cs["run_at"] as? String) == "document_start" ? .atDocumentStart : .atDocumentEnd
                let allFrames = (cs["all_frames"] as? Bool) ?? false
                let src = Self.wrap(patterns: patterns, excludes: excludes, css: css, js: js)
                scripts.append(WKUserScript(source: src, injectionTime: runAt, forMainFrameOnly: !allFrames))
                injected += 1
            }
            names.append(injected > 0 ? name : "\(name)(注入対象なし)")
        }
    }

    func apply(to ucc: WKUserContentController) {
        scripts.forEach { ucc.addUserScript($0) }
    }

    // Chromeのmatchパターン → 正規表現ソース
    static func regexSource(for pattern: String) -> String? {
        if pattern == "<all_urls>" { return "^(https?|file|ftp)://" }
        guard let r = pattern.range(of: "://") else { return nil }
        let scheme = String(pattern[pattern.startIndex..<r.lowerBound])
        let rest = String(pattern[r.upperBound...])
        let host: String, path: String
        if let i = rest.firstIndex(of: "/") {
            host = String(rest[..<i]); path = String(rest[i...])
        } else {
            host = rest; path = "/*"
        }
        let schemeRe = scheme == "*" ? "https?" : NSRegularExpression.escapedPattern(for: scheme)
        let hostRe: String
        if host == "*" {
            hostRe = "[^/]*"
        } else if host.hasPrefix("*.") {
            hostRe = "([^/]+\\.)?" + NSRegularExpression.escapedPattern(for: String(host.dropFirst(2)))
        } else {
            hostRe = NSRegularExpression.escapedPattern(for: host)
        }
        let pathRe = NSRegularExpression.escapedPattern(for: path).replacingOccurrences(of: "\\*", with: ".*")
        return "^\(schemeRe)://\(hostRe)(:\\d+)?\(pathRe)$"
    }

    // Swift文字列 → JS文字列リテラル(JSONエスケープ)
    static func jsLiteral(_ s: String) -> String {
        guard let d = try? JSONEncoder().encode([s]), let a = String(data: d, encoding: .utf8) else { return "\"\"" }
        return String(a.dropFirst().dropLast())
    }

    static func wrap(patterns: [String], excludes: [String], css: String, js: String) -> String {
        let pats = patterns.map { "new RegExp(\(jsLiteral($0)))" }.joined(separator: ",")
        let excl = excludes.map { "new RegExp(\(jsLiteral($0)))" }.joined(separator: ",")
        return """
        (function(){
          var pats=[\(pats)], excl=[\(excl)], href=location.href;
          if(!pats.some(function(p){return p.test(href);})) return;
          if(excl.some(function(p){return p.test(href);})) return;
          window.chrome = window.chrome || {};
          window.chrome.runtime = window.chrome.runtime || { id: "mado", getURL: function(p){ return p; } };
          var css=\(jsLiteral(css));
          if(css.trim()){ var st=document.createElement('style'); st.textContent=css; (document.head||document.documentElement).appendChild(st); }
          \(js)
        })();
        """
    }
}

// MARK: - タブ
final class Tab {
    let webView: WKWebView
    init(webView: WKWebView) { self.webView = webView }
}

// MARK: - ウィンドウ(1ウィンドウ=1ブラウザ)
final class BrowserWindowController: NSWindowController, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate, NSTextFieldDelegate {

    let isPrivate: Bool
    var tabs: [Tab] = []
    var current: Tab? { tabs.indices.contains(currentIndex) ? tabs[currentIndex] : nil }
    var currentIndex = 0

    // UI
    let container = ThemedView()
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

    var palette: Palette { Palette.current(for: container) }

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

    init(isPrivate: Bool) {
        self.isPrivate = isPrivate
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        win.title = isPrivate ? "Mado — プライベート" : "Mado"
        win.titlebarAppearsTransparent = true
        win.center()
        super.init(window: win)
        win.delegate = self
        buildUI()
        applyTheme()
        loadRules { [weak self] in
            self?.addTab(url: nil)   // スタートは無地。ホームページは読み込まない
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: UI構築
    func buildUI() {
        guard let win = window else { return }
        container.frame = win.contentView!.bounds
        container.autoresizingMask = [.width, .height]
        container.onAppearanceChange = { [weak self] in self?.applyTheme() }
        win.contentView = container

        toolbar.wantsLayer = true
        container.addSubview(toolbar)

        tabBar.orientation = .horizontal
        tabBar.spacing = 4
        tabBar.alignment = .centerY
        container.addSubview(tabBar)

        backBtn.title = "‹"; backBtn.target = self; backBtn.action = #selector(goBack)
        fwdBtn.title = "›"; fwdBtn.target = self; fwdBtn.action = #selector(goForward)
        reloadBtn.title = "⟳"; reloadBtn.target = self; reloadBtn.action = #selector(reload)
        for b in [backBtn, fwdBtn, reloadBtn] {
            b.bezelStyle = .regularSquare; b.isBordered = false
            b.font = NSFont.systemFont(ofSize: 20)
            toolbar.addSubview(b)
        }

        // Shields(広告・トラッカー遮断)ボタン — SFシンボルの盾
        shieldBtn.image = NSImage(systemSymbolName: "shield", accessibilityDescription: "Shields")
        shieldBtn.bezelStyle = .regularSquare; shieldBtn.isBordered = false
        shieldBtn.target = self; shieldBtn.action = #selector(toggleShields)
        shieldBtn.toolTip = "広告・トラッカー遮断のオン/オフ"
        toolbar.addSubview(shieldBtn)

        urlField.placeholderString = "検索または URL を入力"
        urlField.font = NSFont.systemFont(ofSize: 13)
        urlField.wantsLayer = true
        urlField.layer?.cornerRadius = 8
        urlField.isBezeled = false
        urlField.drawsBackground = true
        urlField.focusRingType = .none
        urlField.delegate = self
        urlField.target = self
        urlField.action = #selector(navigateFromField)
        urlField.usesSingleLineMode = true
        (urlField.cell as? NSTextFieldCell)?.usesSingleLineMode = true
        toolbar.addSubview(urlField)

        newTabBtn.title = "＋"; newTabBtn.bezelStyle = .regularSquare; newTabBtn.isBordered = false
        newTabBtn.font = NSFont.systemFont(ofSize: 18)
        newTabBtn.target = self; newTabBtn.action = #selector(newTabAction)
        container.addSubview(newTabBtn)

        starBtn.title = "☆"
        starBtn.bezelStyle = .regularSquare; starBtn.isBordered = false
        starBtn.font = NSFont.systemFont(ofSize: 17)
        starBtn.target = self; starBtn.action = #selector(toggleBookmark)
        starBtn.toolTip = "このページをブックマーク"
        toolbar.addSubview(starBtn)

        // ブックマークバー
        bookmarkBar.orientation = .horizontal
        bookmarkBar.spacing = 4
        bookmarkBar.alignment = .centerY
        bookmarkBar.wantsLayer = true
        container.addSubview(bookmarkBar)

        // ページ内検索フィールド(⌘F)
        findField.placeholderString = "ページ内を検索…"
        findField.font = NSFont.systemFont(ofSize: 12)
        findField.wantsLayer = true
        findField.layer?.cornerRadius = 6
        findField.isBezeled = false
        findField.drawsBackground = true
        findField.focusRingType = .none
        findField.isHidden = true
        findField.target = self
        findField.action = #selector(performFind)
        container.addSubview(findField)

        refreshBookmarkBar()

        webHost.wantsLayer = true
        container.addSubview(webHost)

        layout()
    }

    // テーマ配色を全UIへ反映
    func applyTheme() {
        let p = palette
        window?.backgroundColor = p.bg
        toolbar.layer?.backgroundColor = p.bar.cgColor
        webHost.layer?.backgroundColor = p.bg.cgColor
        bookmarkBar.layer?.backgroundColor = p.bg.cgColor
        urlField.textColor = p.text
        urlField.backgroundColor = p.field
        findField.textColor = p.text
        findField.backgroundColor = p.bar
        for b in [backBtn, fwdBtn, reloadBtn, newTabBtn, shieldBtn] { b.contentTintColor = p.text }
        for tab in tabs { tab.webView.underPageBackgroundColor = p.bg }
        updateStar()
        refreshTabBar()
        refreshBookmarkBar()
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
            forIdentifier: "mado-shields", encodedContentRuleList: Blocklist.json()
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
        ExtensionManager.shared.apply(to: ucc)
        cfg.userContentController = ucc
        let wv = WKWebView(frame: webHost.bounds, configuration: cfg)
        wv.autoresizingMask = [.width, .height]
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.allowsBackForwardNavigationGestures = true
        wv.underPageBackgroundColor = palette.bg
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        return wv
    }

    @discardableResult
    func addTab(url: URL?) -> Tab {
        let tab = Tab(webView: makeWebView())
        tab.webView.isHidden = (url == nil)   // 未読み込みのタブは無地のスタート画面
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
            window?.makeFirstResponder(wv.isHidden ? urlField : wv)
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
        let p = palette
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
            btn.layer?.backgroundColor = (i == currentIndex ? p.tabActive : p.bg).cgColor
            btn.contentTintColor = p.text
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
    @objc func newTabAction() { addTab(url: nil) }

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
        if let tab = current {
            tab.webView.isHidden = false
            tab.webView.load(URLRequest(url: url))
        } else {
            addTab(url: url)
        }
    }

    func searchURL(_ q: String) -> URL {
        let e = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        return URL(string: "https://duckduckgo.com/?q=\(e)")!
    }

    func syncURLField() {
        urlField.stringValue = current?.webView.url?.absoluteString ?? ""
        updateStar()
    }

    func updateStar() {
        let url = current?.webView.url?.absoluteString ?? ""
        let marked = !url.isEmpty && BrowserWindowController.loadBookmarks().contains { $0.url == url }
        starBtn.title = marked ? "★" : "☆"
        starBtn.contentTintColor = palette.text
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
        let p = palette
        bookmarkBar.arrangedSubviews.forEach { bookmarkBar.removeArrangedSubview($0); $0.removeFromSuperview() }
        for (i, bm) in BrowserWindowController.loadBookmarks().enumerated() {
            let btn = NSButton(title: String(bm.title.prefix(16)), target: self, action: #selector(openBookmark(_:)))
            btn.tag = i
            btn.bezelStyle = .regularSquare; btn.isBordered = false
            btn.font = NSFont.systemFont(ofSize: 11)
            btn.contentTintColor = p.text
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 6
            btn.layer?.backgroundColor = p.bar.cgColor
            btn.heightAnchor.constraint(equalToConstant: 22).isActive = true
            bookmarkBar.addArrangedSubview(btn)
        }
    }

    @objc func openBookmark(_ s: NSButton) {
        let bms = BrowserWindowController.loadBookmarks()
        guard bms.indices.contains(s.tag), let url = URL(string: bms[s.tag].url) else { return }
        if let tab = current {
            tab.webView.isHidden = false
            tab.webView.load(URLRequest(url: url))
        } else {
            addTab(url: url)
        }
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
        wv.isHidden = false
        syncURLField(); refreshTabBar()
    }
    func webView(_ wv: WKWebView, didCommit nav: WKNavigation!) {
        wv.isHidden = false
        syncURLField()
    }

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
    var themeItems: [ThemeMode: NSMenuItem] = [:]

    func applicationDidFinishLaunching(_ n: Notification) {
        ThemeMode.apply()
        ExtensionManager.shared.reload()
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

    // テーマ
    @objc func themeSystem() { setTheme(.system) }
    @objc func themeLight() { setTheme(.light) }
    @objc func themeDark() { setTheme(.dark) }
    func setTheme(_ m: ThemeMode) {
        ThemeMode.set(m)
        updateThemeMenu()
        for wc in windows { wc.applyTheme() }
    }
    func updateThemeMenu() {
        for (mode, item) in themeItems { item.state = (mode == ThemeMode.current) ? .on : .off }
    }

    // 拡張機能
    @objc func openExtensionsFolder() {
        ExtensionManager.shared.ensureDirectory()
        NSWorkspace.shared.open(ExtensionManager.directory)
    }
    @objc func reloadExtensions() {
        ExtensionManager.shared.reload()
        for wc in windows {
            for tab in wc.tabs {
                let ucc = tab.webView.configuration.userContentController
                ucc.removeAllUserScripts()
                ExtensionManager.shared.apply(to: ucc)
            }
        }
        let alert = NSAlert()
        alert.messageText = "拡張機能を再読み込みしました"
        let names = ExtensionManager.shared.names
        alert.informativeText = names.isEmpty
            ? "拡張機能は見つかりませんでした。フォルダに展開済み(unpacked)のChrome拡張を置いてください。"
            : names.joined(separator: "\n") + "\n\n次のページ読み込みから適用されます。"
        alert.runModal()
    }

    func setupMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Mado Proについて", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Mado Proを終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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

        // 表示(テーマ)
        let viewItem = NSMenuItem(); main.addItem(viewItem)
        let viewMenu = NSMenu(title: "表示")
        let themeSub = NSMenu(title: "テーマ")
        let sysItem = NSMenuItem(title: "システムに合わせる", action: #selector(themeSystem), keyEquivalent: "")
        let lightItem = NSMenuItem(title: "ライト", action: #selector(themeLight), keyEquivalent: "")
        let darkItem = NSMenuItem(title: "ダーク", action: #selector(themeDark), keyEquivalent: "")
        themeItems = [.system: sysItem, .light: lightItem, .dark: darkItem]
        for i in [sysItem, lightItem, darkItem] { themeSub.addItem(i) }
        let themeItem = NSMenuItem(title: "テーマ", action: nil, keyEquivalent: "")
        themeItem.submenu = themeSub
        viewMenu.addItem(themeItem)
        viewItem.submenu = viewMenu
        updateThemeMenu()

        // 拡張機能
        let extItem = NSMenuItem(); main.addItem(extItem)
        let extMenu = NSMenu(title: "拡張機能")
        extMenu.addItem(withTitle: "拡張機能フォルダを開く", action: #selector(openExtensionsFolder), keyEquivalent: "")
        extMenu.addItem(withTitle: "拡張機能を再読み込み", action: #selector(reloadExtensions), keyEquivalent: "")
        extItem.submenu = extMenu

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
