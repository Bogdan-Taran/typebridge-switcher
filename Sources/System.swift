import AppKit
import Carbon
import ApplicationServices
import ServiceManagement

final class Preferences {
    let defaults = UserDefaults.standard
    init() {
        defaults.register(defaults: ["enabled": true, "sensitivity": 1,
            "english": "com.apple.keylayout.ABC", "russian": "com.apple.keylayout.Russian",
            "excludedApps": "com.apple.Terminal\ncom.googlecode.iterm2\ncom.microsoft.VSCode\ncom.apple.dt.Xcode\ncom.todesktop.230313mzl4w4u92\ncom.agilebits.onepassword7\ncom.1password.1password",
            "exceptions": "API URL HTTP HTTPS JSON HTML CSS SQL SSH VPN DNS CPU GPU RAM SSD USB UUID npm git sudo docker localhost macOS iOS OpenAI ChatGPT", "customWords": ""])
    }
    var enabled: Bool { get { defaults.bool(forKey: "enabled") } set { defaults.set(newValue, forKey: "enabled") } }
    var sensitivity: Sensitivity { get { Sensitivity(rawValue: defaults.integer(forKey: "sensitivity")) ?? .balanced } set { defaults.set(newValue.rawValue, forKey: "sensitivity") } }
    func string(_ key: String) -> String { defaults.string(forKey: key) ?? "" }
    func set(_ key: String, _ value: String) { defaults.set(value, forKey: key) }
    func list(_ key: String) -> Set<String> {
        Set(string(key).lowercased().split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init))
    }
}

struct InputLayout {
    let source: TISInputSource
    let id: String
    let name: String
}

final class Layouts {
    let prefs: Preferences
    init(_ prefs: Preferences) { self.prefs = prefs }
    func property(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
    func available() -> [InputLayout] {
        let filter = [kTISPropertyInputSourceType as String: kTISTypeKeyboardLayout as String,
                      kTISPropertyInputSourceIsSelectCapable as String: true] as CFDictionary
        let sources = TISCreateInputSourceList(filter, false).takeRetainedValue() as! [TISInputSource]
        return sources.compactMap { source in
            guard let id = property(source, kTISPropertyInputSourceID), let name = property(source, kTISPropertyLocalizedName) else { return nil }
            return InputLayout(source: source, id: id, name: name)
        }
    }
    func id(for language: Language) -> String { prefs.string(language == .en ? "english" : "russian") }
    func currentID() -> String {
        property(TISCopyCurrentKeyboardInputSource().takeRetainedValue(), kTISPropertyInputSourceID) ?? ""
    }
    func currentLanguage() -> Language? {
        let current = currentID()
        return current == id(for: .en) ? .en : current == id(for: .ru) ? .ru : nil
    }
    func select(_ language: Language) -> Bool {
        guard let layout = available().first(where: { $0.id == id(for: language) }) else { return false }
        return TISSelectInputSource(layout.source) == noErr
    }
    var ready: Bool {
        let ids = Set(available().map(\.id))
        return id(for: .en) != id(for: .ru) && ids.contains(id(for: .en)) && ids.contains(id(for: .ru))
    }
    func chooseInitialDefaults() {
        let all = available()
        if !all.contains(where: { $0.id == id(for: .en) }),
           let source = all.first(where: { $0.id == "com.apple.keylayout.US" || $0.id.contains("British") }) { prefs.set("english", source.id) }
        if !all.contains(where: { $0.id == id(for: .ru) }),
           let source = all.first(where: { $0.id.contains("Russian") && !$0.id.contains("Phonetic") }) { prefs.set("russian", source.id) }
    }
    func makeMap() -> KeyboardMap {
        let all = available()
        guard let en = all.first(where: { $0.id == id(for: .en) }),
              let ru = all.first(where: { $0.id == id(for: .ru) }) else { return KeyboardMap() }
        var pairs: [(Character, Character)] = []
        for key in UInt16(0)..<UInt16(51) {
            for shifted in [false, true] {
                if let e = character(en.source, key: key, shifted: shifted),
                   let r = character(ru.source, key: key, shifted: shifted),
                   e.isLetter || r.isLetter { pairs.append((e, r)) }
            }
        }
        return KeyboardMap(pairs: pairs)
    }
    private func character(_ source: TISInputSource, key: UInt16, shifted: Bool) -> Character? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
        let layout = UnsafeRawPointer(CFDataGetBytePtr(data)!).assumingMemoryBound(to: UCKeyboardLayout.self)
        var dead: UInt32 = 0; var length = 0
        var chars = [UniChar](repeating: 0, count: 8)
        let status = UCKeyTranslate(layout, key, UInt16(kUCKeyActionDown), shifted ? 2 : 0,
            UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask), &dead, 8, &length, &chars)
        guard status == noErr, length == 1 else { return nil }
        return String(utf16CodeUnits: chars, count: length).first
    }
}

struct Focus {
    let element: AXUIElement
    let cursor: Int
    func textBefore(_ count: Int) -> String? {
        guard count > 0, cursor >= count else { return count == 0 ? "" : nil }
        var range = CFRange(location: cursor - count, length: count)
        guard let value = AXValueCreate(.cfRange, &range) else { return nil }
        var result: CFTypeRef?
        if AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, value, &result) == .success {
            return result as? String
        }
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &result) == .success,
           let string = result as? String, cursor <= (string as NSString).length {
            return (string as NSString).substring(with: NSRange(location: cursor - count, length: count))
        }
        return nil
    }
    static func read(pid: pid_t) -> Focus? {
        guard !IsSecureEventInputEnabled() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.025)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.025)
        var subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        guard subrole as? String != "AXSecureTextField" else { return nil }
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selected) == .success,
              let selected, CFGetTypeID(selected) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(selected as! AXValue, .cfRange, &range), range.length == 0, range.location >= 0 else { return nil }
        return Focus(element: element, cursor: range.location)
    }
}

final class KeyboardMonitor {
    let prefs: Preferences
    let layouts: Layouts
    let detector: Detector
    var onChange: (() -> Void)?
    private(set) var status = "Ожидает разрешения"
    private(set) var eventCount = 0
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var token = ""
    private var anchor = 0
    private var focusElement: AXUIElement?
    private var language: Language?
    private var originalLanguage: Language?
    private var locked = false
    private var lastPID: pid_t = 0
    private var suppressedKeys: Set<Int64> = []
    private var lastInputTime = Date.distantPast
    private let marker: Int64 = 0x545950454252

    init(_ prefs: Preferences, _ layouts: Layouts, _ detector: Detector) {
        self.prefs = prefs; self.layouts = layouts; self.detector = detector
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in self?.reset() }
    }
    func reset() { token = ""; focusElement = nil; language = nil; originalLanguage = nil; locked = false }
    func refresh() {
        reset()
        detector.map = layouts.makeMap(); detector.sensitivity = prefs.sensitivity
        detector.exceptions = prefs.list("exceptions"); detector.customWords = prefs.list("customWords")
    }
    var running: Bool { tap != nil && AXIsProcessTrusted() }
    func start() {
        guard tap == nil else { return }
        guard AXIsProcessTrusted() else { status = "Нужен доступ «Универсальный доступ»"; return }
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: { proxy, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                return Unmanaged<KeyboardMonitor>.fromOpaque(context).takeUnretainedValue().handle(proxy, type, event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { status = "Нет доступа к клавиатуре — проверьте разрешения"; return }
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        status = "Готово к работе"; onChange?()
    }
    private func handle(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .keyDown { eventCount += 1 }
        if event.getIntegerValueField(.eventSourceUserData) == marker { return pass }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            reset(); if let tap { CGEvent.tapEnable(tap: tap, enable: true) }; return pass
        }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp { return suppressedKeys.remove(key) != nil ? nil : pass }
        if type == .flagsChanged {
            if !event.flags.intersection([.maskCommand, .maskControl]).isEmpty { reset() }
            return pass
        }
        guard type == .keyDown else { reset(); return pass }
        guard prefs.enabled, layouts.ready, !IsSecureEventInputEnabled(),
              let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier,
              !prefs.list("excludedApps").contains((app.bundleIdentifier ?? "").lowercased()) else { reset(); return pass }
        if app.processIdentifier != lastPID || Date().timeIntervalSince(lastInputTime) > 30 { reset() }
        lastPID = app.processIdentifier; lastInputTime = Date()
        guard let current = layouts.currentLanguage(), let focus = Focus.read(pid: lastPID) else { reset(); return pass }
        if let tracked = focusElement, (!CFEqual(tracked, focus.element) || focus.cursor != anchor + token.utf16.count || language != current) { reset() }
        let flags = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
        let manual = key == 49 && flags == .maskAlternate
        let undo = key == 53 && flags.isEmpty && originalLanguage != nil
        if manual || undo {
            guard !token.isEmpty, let mapped = detector.map.convert(token, from: current),
                  replace(proxy, focus: focus, previous: token, result: mapped, to: current.other) else { reset(); return pass }
            token = mapped; language = current.other; locked = true; originalLanguage = nil
            suppressedKeys.insert(key); return nil
        }
        guard flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty else { reset(); return pass }
        if key == 51 { // Plain Backspace keeps the tracked word coherent.
            if !token.isEmpty { token.removeLast() } else { reset() }
            return pass
        }
        guard ![53, 117, 123, 124, 125, 126, 115, 119, 116, 121].contains(key),
              event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { reset(); return pass }
        var length = 0; var chars = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &length, unicodeString: &chars)
        guard length > 0 else { reset(); return pass }
        let typed = String(utf16CodeUnits: chars, count: length)
        guard typed.count == 1, let character = typed.first else { reset(); return pass }
        let boundary = character.isWhitespace || [36, 48, 49, 76].contains(key)
        if boundary {
            if !locked, let converted = detector.correction(token, from: current, boundary: true),
               replace(proxy, focus: focus, previous: token, result: converted, to: current.other) {
                // Replay the original separator after the replacement in the same event stream.
                event.setIntegerValueField(.eventSourceUserData, value: marker)
                event.tapPostEvent(proxy)
                suppressedKeys.insert(key)
                if let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(key), keyDown: false) {
                    up.setIntegerValueField(.eventSourceUserData, value: marker); up.tapPostEvent(proxy)
                }
                reset(); return nil
            }
            reset(); return pass
        }
        guard character.isLetter || "[];',.`".contains(character) else { reset(); return pass }
        if token.isEmpty {
            // Never change the tail of an existing identifier or a word after cursor movement.
            if focus.cursor > 0 {
                guard let preceding = focus.textBefore(1), let c = preceding.last,
                      c.isWhitespace || "([{\"«—–".contains(c) else { reset(); return pass }
            }
            anchor = focus.cursor; focusElement = focus.element; language = current
        }
        guard token.count < 48 else { reset(); return pass }
        let candidate = token + typed
        if !locked, let converted = detector.correction(candidate, from: current, boundary: false),
           replace(proxy, focus: focus, previous: token, result: converted, to: current.other) {
            token = converted; language = current.other; originalLanguage = current; locked = true
            suppressedKeys.insert(key); return nil
        }
        token = candidate
        return pass
    }
    private func replace(_ proxy: CGEventTapProxy, focus: Focus, previous: String, result: String, to target: Language) -> Bool {
        guard focus.textBefore(previous.utf16.count) == previous,
              !IsSecureEventInputEnabled(), NSWorkspace.shared.frontmostApplication?.processIdentifier == lastPID else { return false }
        // Allocate all events before changing anything. No clipboard or persistent text history.
        var events: [CGEvent] = []
        for _ in previous {
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 51, keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: 51, keyDown: false) else { return false }
            events += [down, up]
        }
        for char in result {
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else { return false }
            let utf16 = Array(String(char).utf16)
            down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            events += [down, up]
        }
        guard layouts.select(target) else { return false }
        for event in events {
            event.flags = []; event.setIntegerValueField(.eventSourceUserData, value: marker)
            event.tapPostEvent(proxy)
        }
        return true
    }
}
