import AppKit
import ApplicationServices
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let prefs = Preferences()
    let detector = Detector()
    lazy var layouts = Layouts(prefs)
    lazy var monitor = KeyboardMonitor(prefs, layouts, detector)
    var item: NSStatusItem!
    var window: NSWindow?
    var statusLabel: NSTextField?
    var loginButton: NSButton?
    var enabledButton: NSButton?
    var sensitivityPopup: NSPopUpButton?
    var englishPopup: NSPopUpButton?
    var russianPopup: NSPopUpButton?
    var fields: [String: NSTextView] = [:]
    var timer: Timer?
    var loginError = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A single menu item and a single event tap, even if the bundle is opened twice.
        let id = Bundle.main.bundleIdentifier ?? "local.TypeBridge"
        if NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 { NSApp.terminate(nil); return }
        layouts.chooseInitialDefaults()
        let checker = NSSpellChecker.shared
        let languages = checker.availableLanguages
        detector.spelling = { text, language in
            guard let code = languages.first(where: { $0.hasPrefix(language.rawValue) }) else { return false }
            return checker.checkSpelling(of: text, startingAt: 0, language: code,
                wrap: false, inSpellDocumentWithTag: 0, wordCount: nil).location == NSNotFound
        }
        monitor.refresh()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        monitor.onChange = { [weak self] in self?.updateStatus() }
        monitor.start()
        let smokeTest = CommandLine.arguments.contains("--smoke-test")
        let firstLaunch = !prefs.defaults.bool(forKey: "didLaunch")
        if firstLaunch && !smokeTest {
            prefs.defaults.set(true, forKey: "didLaunch")
            do { try SMAppService.mainApp.register() } catch { loginError = error.localizedDescription }
        }
        updateStatus()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.monitor.start(); self.updateStatus()
        }
        if firstLaunch || !monitor.running { showSettings() }
        if smokeTest {
            showSettings()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.window?.contentView?.layoutSubtreeIfNeeded()
                if let content = self.window?.contentView, let stack = content.subviews.first as? NSStackView,
                   let last = stack.arrangedSubviews.last {
                    let rect = last.convert(last.bounds, to: content)
                    precondition(rect.minY >= 0 && rect.maxY <= content.bounds.height, "Settings controls are clipped")
                }
                if self.layouts.ready {
                    let map = self.layouts.makeMap()
                    precondition(map.convert("ghbdtn", from: .en) == "привет", "Native layout mapping RU failed")
                    precondition(map.convert("руддщ", from: .ru) == "hello", "Native layout mapping EN failed")
                    print("Native keyboard layouts: mapping verified in both directions")
                }
                print("SMOKE OK: menu, settings window, layout enumeration, detector initialized")
                NSApp.terminate(nil)
            }
        }
    }

    func updateStatus() {
        let active = prefs.enabled && monitor.running && layouts.ready
        item?.button?.title = active ? "EN ⇄ RU" : "EN · RU"
        item?.button?.appearsDisabled = !active
        item?.button?.toolTip = "TypeBridge — " + (active ? "автопереключение включено" : "пауза / требуется настройка")
        let menu = NSMenu()
        let title = NSMenuItem(title: "TypeBridge", action: nil, keyEquivalent: "")
        menu.addItem(title)
        let toggle = NSMenuItem(title: "Автопереключение", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self; toggle.state = prefs.enabled ? .on : .off; menu.addItem(toggle)
        menu.addItem(.separator())
        addMenu(menu, "Настройки…", #selector(showSettings), ",")
        addMenu(menu, "Исключить текущее приложение", #selector(excludeCurrent))
        menu.addItem(NSMenuItem(title: "⌥ Пробел — исправить текущее слово", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Esc — отменить до пробела", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        addMenu(menu, "Завершить TypeBridge", #selector(quit), "q")
        item?.menu = menu
        var state = !prefs.enabled ? "На паузе" : !layouts.ready ? "Добавьте и выберите две раскладки" : monitor.status
        if !AXIsProcessTrusted() { state = "Разрешите «Универсальный доступ» для TypeBridge" }
        let login = SMAppService.mainApp.status
        if login == .requiresApproval { state += " · Подтвердите автозапуск в настройках macOS" }
        if !loginError.isEmpty { state += " · Автозапуск: " + loginError }
        if CommandLine.arguments.contains("--diagnostics") { state += " · Событий клавиатуры: \(monitor.eventCount)" }
        statusLabel?.stringValue = state
        enabledButton?.state = prefs.enabled ? .on : .off
        loginButton?.state = login == .enabled || login == .requiresApproval ? .on : .off
    }
    func addMenu(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "") {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key); entry.target = self; menu.addItem(entry)
    }
    @objc func toggleEnabled() { prefs.enabled.toggle(); monitor.reset(); updateStatus() }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func excludeCurrent() {
        guard let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier,
              id != Bundle.main.bundleIdentifier else { return }
        var excluded = prefs.list("excludedApps"); excluded.insert(id.lowercased())
        prefs.set("excludedApps", excluded.sorted().joined(separator: "\n"))
        fields["excludedApps"]?.string = prefs.string("excludedApps")
        monitor.reset()
    }
    @objc func accessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openURL("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }
    @objc func inputMonitoring() { openURL("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") }
    @objc func keyboardSettings() { openURL("x-apple.systempreferences:com.apple.Keyboard-Settings.extension") }
    @objc func loginSettings() { SMAppService.openSystemSettingsLoginItems() }
    func openURL(_ value: String) { if let url = URL(string: value) { NSWorkspace.shared.open(url) } }
    @objc func changeLogin(_ sender: NSButton) {
        loginError = ""
        do {
            if sender.state == .on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch { loginError = error.localizedDescription }
        updateStatus()
    }
    @objc func save() {
        if let sensitivityPopup { prefs.sensitivity = Sensitivity(rawValue: sensitivityPopup.indexOfSelectedItem) ?? .balanced }
        if let id = englishPopup?.selectedItem?.representedObject as? String { prefs.set("english", id) }
        if let id = russianPopup?.selectedItem?.representedObject as? String { prefs.set("russian", id) }
        for (key, view) in fields { prefs.set(key, view.string) }
        monitor.refresh(); updateStatus()
    }
    @objc func refreshLayouts() { populateLayouts(); monitor.refresh(); updateStatus() }
    func populateLayouts() {
        let all = layouts.available()
        for (popup, language) in [(englishPopup, Language.en), (russianPopup, .ru)] {
            guard let popup else { continue }
            popup.removeAllItems()
            popup.addItem(withTitle: "Выберите раскладку…")
            for source in all {
                popup.addItem(withTitle: source.name)
                popup.lastItem?.representedObject = source.id
                if source.id == layouts.id(for: language) { popup.select(popup.lastItem) }
            }
        }
    }

    @objc func showSettings() {
        if let window { NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 755),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "TypeBridge · Настройки"; window.isReleasedWhenClosed = false
        window.delegate = self; self.window = window
        let content = NSView(); window.contentView = content
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24)
        ])
        func label(_ text: String, _ size: CGFloat = 13, bold: Bool = false) -> NSTextField {
            let label = NSTextField(wrappingLabelWithString: text)
            label.font = bold ? .systemFont(ofSize: size, weight: .semibold) : .systemFont(ofSize: size)
            label.preferredMaxLayoutWidth = 640
            label.setContentCompressionResistancePriority(.required, for: .vertical)
            return label
        }
        func button(_ title: String, _ action: Selector) -> NSButton { NSButton(title: title, target: self, action: action) }
        func row(_ views: [NSView]) -> NSStackView {
            let row = NSStackView(views: views); row.orientation = .horizontal; row.spacing = 10; row.alignment = .centerY
            return row
        }
        func editor(_ key: String, _ height: CGFloat) -> NSScrollView {
            let scroll = NSScrollView(); scroll.borderType = .bezelBorder; scroll.hasVerticalScroller = true
            let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 630, height: height))
            view.isRichText = false; view.font = .systemFont(ofSize: 12)
            view.isAutomaticQuoteSubstitutionEnabled = false; view.isAutomaticDashSubstitutionEnabled = false
            view.isAutomaticSpellingCorrectionEnabled = false; view.isContinuousSpellCheckingEnabled = false
            view.textContainerInset = NSSize(width: 7, height: 5)
            view.isVerticallyResizable = true; view.isHorizontallyResizable = false
            view.autoresizingMask = [.width]; view.textContainer?.widthTracksTextView = true
            view.string = prefs.string(key); scroll.documentView = view; fields[key] = view
            scroll.heightAnchor.constraint(equalToConstant: height).isActive = true
            scroll.widthAnchor.constraint(equalToConstant: 644).isActive = true
            return scroll
        }
        stack.addArrangedSubview(label("Пишите. Раскладка подстроится.", 25, bold: true))
        stack.addArrangedSubview(label("ghbdtn → привет    ·    руддщ → hello\nЛокально на Mac. Без истории ввода и доступа к буферу обмена."))
        statusLabel = label("", 12); statusLabel?.textColor = .secondaryLabelColor
        stack.addArrangedSubview(statusLabel!)
        stack.addArrangedSubview(row([button("1. Разрешить доступ", #selector(accessibility)), button("Мониторинг ввода…", #selector(inputMonitoring))]))
        enabledButton = NSButton(checkboxWithTitle: "Автоматически исправлять раскладку", target: self, action: #selector(toggleEnabled))
        loginButton = NSButton(checkboxWithTitle: "Запускать при входе в macOS", target: self, action: #selector(changeLogin(_:)))
        stack.addArrangedSubview(row([enabledButton!, loginButton!]))
        englishPopup = NSPopUpButton(); russianPopup = NSPopUpButton()
        englishPopup?.widthAnchor.constraint(equalToConstant: 200).isActive = true
        russianPopup?.widthAnchor.constraint(equalToConstant: 200).isActive = true
        populateLayouts()
        stack.addArrangedSubview(row([label("EN"), englishPopup!, label("RU"), russianPopup!, button("↻", #selector(refreshLayouts))]))
        stack.addArrangedSubview(row([button("Раскладки macOS…", #selector(keyboardSettings)), button("Автозапуск macOS…", #selector(loginSettings))]))
        sensitivityPopup = NSPopUpButton()
        sensitivityPopup?.addItems(withTitles: ["Осторожно — после пробела", "Сбалансированно — от 3 букв", "Быстро — от 2 букв"])
        sensitivityPopup?.selectItem(at: prefs.sensitivity.rawValue)
        stack.addArrangedSubview(row([label("Чувствительность"), sensitivityPopup!]))
        stack.addArrangedSubview(label("⌥ Пробел — переключить текущее слово. Esc — отменить автозамену до пробела.\nКороткие неоднозначные слова сохраняются. В быстрых режимах возможны ошибки.", 12))
        stack.addArrangedSubview(label("Не исправлять эти слова · через пробел или запятую", 12, bold: true))
        stack.addArrangedSubview(editor("exceptions", 44))
        stack.addArrangedSubview(label("Мои слова · правильное написание по-русски или по-английски", 12, bold: true))
        stack.addArrangedSubview(editor("customWords", 40))
        stack.addArrangedSubview(label("Исключённые приложения · идентификаторы, по одному на строку", 12, bold: true))
        stack.addArrangedSubview(editor("excludedApps", 58))
        let saveButton = button("Сохранить настройки", #selector(save)); saveButton.keyEquivalent = "\r"
        stack.addArrangedSubview(row([saveButton, label("Приложение работает через значок EN ⇄ RU в строке меню.", 11)]))
        window.center(); NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
        updateStatus()
    }
    func windowWillClose(_ notification: Notification) { save() }
}
