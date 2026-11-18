// Wheelhouse - a mouse utility for macOS.
// Smooth wheel scrolling, cursor speed without acceleration, extra-button
// actions and drag gestures, per-app exceptions, key swaps, report-rate meter.
// Single file, AppKit + SwiftUI, macOS 13+. Build with ./build.sh

import Cocoa
import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers

// MARK: - Settings model

enum ActionKind: String, Codable, CaseIterable, Identifiable {
    case none, originalClick, shortcut, missionControl, appExpose, spaceLeft, spaceRight,
         showDesktop, back, forward, openRun
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "Do nothing"
        case .originalClick: return "Normal click"
        case .shortcut: return "Keyboard shortcut"
        case .missionControl: return "Mission Control"
        case .appExpose: return "App windows"
        case .spaceLeft: return "Space to the left"
        case .spaceRight: return "Space to the right"
        case .showDesktop: return "Show desktop"
        case .back: return "Back (⌘[)"
        case .forward: return "Forward (⌘])"
        case .openRun: return "Open or run…"
        }
    }
}

struct MouseAction: Codable, Equatable {
    var kind: ActionKind = .none
    var keyCode: Int = -1
    var mods: UInt64 = 0
    var target: String = ""
    init(_ kind: ActionKind = .none) { self.kind = kind }
}

enum DragMode: String, Codable, CaseIterable, Identifiable {
    case none, pan, gestures
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "Nothing"
        case .pan: return "Drag to scroll"
        case .gestures: return "Gestures (up, down, left, right)"
        }
    }
}

enum ModAction: String, Codable, CaseIterable, Identifiable {
    case none, horizontal, slow, fast, zoom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "Nothing"
        case .horizontal: return "Scroll sideways"
        case .slow: return "Scroll slower"
        case .fast: return "Scroll faster"
        case .zoom: return "Zoom (⌘+ / ⌘−)"
        }
    }
}

struct ButtonRule: Codable, Identifiable, Equatable {
    var id = UUID()
    var button: Int = 2
    var cmd = false, opt = false, ctrl = false, shift = false
    var click = MouseAction(.originalClick)
    var drag: DragMode = .none
    var up = MouseAction(), down = MouseAction(), left = MouseAction(), right = MouseAction()
}

struct AppException: Codable, Identifiable, Equatable {
    var id = UUID()
    var bundleID: String
    var name: String
    var noScroll = true
    var noButtons = true
}

struct KeySwap: Codable, Identifiable, Equatable {
    var id = UUID()
    var from: Int = -1
    var to: Int = -1
}

struct Config: Codable, Equatable {
    var enabled = true
    // Scrolling
    var smooth = true
    var scrollSpeed = 1.0          // multiplier on distance per notch
    var scrollDuration = 0.30      // seconds a glide lasts
    var scrollAccel = 1.0          // 0 = none
    var discreteLines = 3
    var discreteAccel = false
    var reverseV = false
    var reverseH = false
    var cmdScroll = ModAction.none
    var optScroll = ModAction.slow
    var ctrlScroll = ModAction.none
    var shiftScroll = ModAction.horizontal
    // Cursor
    var cursorOverride = false
    var disableAccel = true
    var cursorSpeed = 1.0
    var cursorAccel = 0.7
    // Buttons
    var panSpeed = 1.5
    var panInvert = false
    var buttons: [ButtonRule] = Config.defaultButtons
    // Other
    var exceptions: [AppException] = []
    var keySwaps: [KeySwap] = []
    var hideIcon = false

    static var defaultButtons: [ButtonRule] {
        var middle = ButtonRule(); middle.button = 2; middle.click = MouseAction(.originalClick); middle.drag = .pan
        var back = ButtonRule(); back.button = 3; back.click = MouseAction(.back); back.drag = .gestures
        back.up = MouseAction(.missionControl); back.down = MouseAction(.appExpose)
        back.left = MouseAction(.spaceRight); back.right = MouseAction(.spaceLeft)
        var fwd = ButtonRule(); fwd.button = 4; fwd.click = MouseAction(.forward)
        return [middle, back, fwd]
    }
}

func buttonName(_ b: Int) -> String {
    switch b {
    case 2: return "Middle button"
    case 3: return "Back side button"
    case 4: return "Forward side button"
    default: return "Button \(b + 1)"
    }
}

let keyNames: [Int: String] = [
    0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q",
    13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
    24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I",
    35: "P", 36: "Return", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
    45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "`", 51: "Delete", 53: "Esc", 57: "Caps Lock",
    96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11", 109: "F10", 111: "F12",
    105: "F13", 107: "F14", 113: "F15", 115: "Home", 116: "Page Up", 117: "Fwd Delete", 118: "F4",
    119: "End", 120: "F2", 121: "Page Down", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑",
]

func keyName(_ code: Int) -> String { code < 0 ? "None" : (keyNames[code] ?? "Key \(code)") }

func shortcutName(_ a: MouseAction) -> String {
    if a.keyCode < 0 { return "Record shortcut" }
    let f = CGEventFlags(rawValue: a.mods)
    var s = ""
    if f.contains(.maskControl) { s += "⌃" }
    if f.contains(.maskAlternate) { s += "⌥" }
    if f.contains(.maskShift) { s += "⇧" }
    if f.contains(.maskCommand) { s += "⌘" }
    return s + keyName(a.keyCode)
}

// MARK: - Store (persisted settings, observed by the UI)

final class Store: ObservableObject {
    static let shared = Store()
    var onChange: (() -> Void)?
    @Published var config: Config {
        didSet { if config != oldValue { save(); onChange?() } }
    }
    @Published var rate = 0
    @Published var trusted = false
    @Published var loginTick = 0
    private let key = "WheelhouseConfig"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let c = try? JSONDecoder().decode(Config.self, from: data) {
            config = c
        } else {
            config = Config()
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(config) { UserDefaults.standard.set(data, forKey: key) }
    }
}

// MARK: - Event engine

let tapCallback: CGEventTapCallBack = { _, type, event, _ in
    return Engine.shared.handle(type, event)
}

final class Engine {
    static let shared = Engine()
    var config = Config()
    var tap: CFMachPort?
    var frontBundle = ""
    let magic: Int64 = 0x5748_4C53   // marks events we post ourselves

    // Smooth scrolling state
    var remX = 0.0, remY = 0.0, fracX = 0.0, fracY = 0.0
    var lastNotch = 0.0, streak = 0, lastDirX = 0, lastDirY = 0
    var timer: Timer?
    var lastTick = 0.0
    var postFlags: CGEventFlags = []

    // Button state
    var active: ButtonRule?
    var activeButton = -1
    var moveX = 0.0, moveY = 0.0
    var panning = false

    // Report rate
    var moveCount = 0

    func start() -> Bool {
        if tap != nil { return true }
        let types: [CGEventType] = [.scrollWheel, .otherMouseDown, .otherMouseUp, .otherMouseDragged,
                                    .mouseMoved, .leftMouseDragged, .rightMouseDragged, .keyDown, .keyUp]
        var mask: CGEventMask = 0
        for t in types { mask |= CGEventMask(1) << CGEventMask(t.rawValue) }
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                        options: .defaultTap, eventsOfInterest: mask,
                                        callback: tapCallback, userInfo: nil) else { return false }
        tap = t
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        return true
    }

    var exception: AppException? { config.exceptions.first { $0.bundleID == frontBundle } }

    func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return pass
        }
        if event.getIntegerValueField(.eventSourceUserData) == magic { return pass }

        switch type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged:
            moveCount += 1
            return pass
        case .keyDown, .keyUp:
            return handleKey(event)
        case .scrollWheel:
            return config.enabled ? handleScroll(event) : pass
        case .otherMouseDown:
            return buttonDown(event)
        case .otherMouseDragged:
            moveCount += 1
            return buttonDragged(event)
        case .otherMouseUp:
            return buttonUp(event)
        default:
            return pass
        }
    }

    // MARK: Keys

    func handleKey(_ e: CGEvent) -> Unmanaged<CGEvent>? {
        if config.enabled && !config.keySwaps.isEmpty {
            let code = Int(e.getIntegerValueField(.keyboardEventKeycode))
            if let s = config.keySwaps.first(where: { $0.from == code && $0.from >= 0 && $0.to >= 0 }) {
                e.setIntegerValueField(.keyboardEventKeycode, value: Int64(s.to))
            }
        }
        return Unmanaged.passUnretained(e)
    }

    // MARK: Scrolling

    func handleScroll(_ e: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(e)
        // Trackpads and Magic Mouse already scroll smoothly: leave them alone.
        if e.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 { return pass }
        if exception?.noScroll == true { return pass }
        let dy = e.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let dx = e.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        if dy == 0 && dx == 0 { return pass }
        var sy = Double(dy.signum()), sx = Double(dx.signum())

        let flags = e.flags
        var mod = ModAction.none
        var used: CGEventFlags = []
        let pairs: [(CGEventFlags, ModAction)] = [(.maskCommand, config.cmdScroll), (.maskAlternate, config.optScroll),
                                                  (.maskControl, config.ctrlScroll), (.maskShift, config.shiftScroll)]
        for (f, a) in pairs where a != .none && flags.contains(f) { mod = a; used = f; break }

        if config.reverseV { sy = -sy }
        if config.reverseH { sx = -sx }

        var factor = 1.0
        switch mod {
        case .zoom:
            postKey((sy + sx) > 0 ? 24 : 27, flags: .maskCommand)   // ⌘= / ⌘-
            return nil
        case .horizontal:
            if sx == 0 { sx = sy; sy = 0 }
        case .slow: factor = 0.33
        case .fast: factor = 3
        case .none: break
        }
        postFlags = flags.subtracting(used)

        let dirX = Int(sx), dirY = Int(sy)
        let now = ProcessInfo.processInfo.systemUptime
        if dirX == lastDirX && dirY == lastDirY && now - lastNotch < 0.15 {
            streak += 1
        } else {
            streak = 0
            // Changing direction stops the current glide straight away.
            if (dirY != 0 && lastDirY != 0 && dirY != lastDirY) || (dirX != 0 && lastDirX != 0 && dirX != lastDirX) {
                remX = 0; remY = 0; fracX = 0; fracY = 0
            }
        }
        lastNotch = now; lastDirX = dirX; lastDirY = dirY

        if config.smooth {
            let accel = 1 + config.scrollAccel * min(Double(streak), 15) * 0.15
            let px = 40.0 * config.scrollSpeed * factor * accel
            remY += sy * px
            remX += sx * px
            startGlide()
        } else {
            let accel = config.discreteAccel ? 1 + min(Double(streak), 10) * 0.2 : 1
            let n = Double(config.discreteLines) * factor * accel
            var ly = Int32((sy * n).rounded()), lx = Int32((sx * n).rounded())
            if ly == 0 && sy != 0 { ly = Int32(sy) }
            if lx == 0 && sx != 0 { lx = Int32(sx) }
            postScroll(.line, ly, lx, continuous: false)
        }
        return nil
    }

    func startGlide() {
        if timer != nil { return }
        lastTick = ProcessInfo.processInfo.systemUptime
        let t = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = max(now - lastTick, 0.001)
        lastTick = now
        let tau = max(config.scrollDuration, 0.05) / 3
        let k = 1 - exp(-dt / tau)
        var stepY = remY * k, stepX = remX * k
        if abs(remY) < 1 { stepY = remY }
        if abs(remX) < 1 { stepX = remX }
        remY -= stepY; remX -= stepX
        fracY += stepY; fracX += stepX
        let iy = Int32(fracY.rounded(.towardZero)), ix = Int32(fracX.rounded(.towardZero))
        fracY -= Double(iy); fracX -= Double(ix)
        if iy != 0 || ix != 0 { postScroll(.pixel, iy, ix, continuous: true) }
        if abs(remY) < 0.01 && abs(remX) < 0.01 {
            timer?.invalidate(); timer = nil
            remX = 0; remY = 0; fracX = 0; fracY = 0
        }
    }

    func postScroll(_ units: CGScrollEventUnit, _ y: Int32, _ x: Int32, continuous: Bool) {
        guard let ev = CGEvent(scrollWheelEvent2Source: nil, units: units, wheelCount: 2,
                               wheel1: y, wheel2: x, wheel3: 0) else { return }
        ev.flags = postFlags
        ev.setIntegerValueField(.eventSourceUserData, value: magic)
        if continuous { ev.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1) }
        ev.post(tap: .cgSessionEventTap)
    }

    // MARK: Buttons

    func matchRule(_ btn: Int, _ f: CGEventFlags) -> ButtonRule? {
        config.buttons.first {
            $0.button == btn && $0.cmd == f.contains(.maskCommand) && $0.opt == f.contains(.maskAlternate)
                && $0.ctrl == f.contains(.maskControl) && $0.shift == f.contains(.maskShift)
        }
    }

    func buttonDown(_ e: CGEvent) -> Unmanaged<CGEvent>? {
        let btn = Int(e.getIntegerValueField(.mouseEventButtonNumber))
        if active != nil { return nil }
        guard config.enabled, exception?.noButtons != true, let rule = matchRule(btn, e.flags) else {
            return Unmanaged.passUnretained(e)
        }
        active = rule; activeButton = btn
        moveX = 0; moveY = 0; panning = false
        return nil
    }

    func buttonDragged(_ e: CGEvent) -> Unmanaged<CGEvent>? {
        let btn = Int(e.getIntegerValueField(.mouseEventButtonNumber))
        guard let rule = active, btn == activeButton else { return Unmanaged.passUnretained(e) }
        let dx = Double(e.getIntegerValueField(.mouseEventDeltaX))
        let dy = Double(e.getIntegerValueField(.mouseEventDeltaY))
        moveX += dx; moveY += dy
        if rule.drag == .pan {
            if !panning && hypot(moveX, moveY) > 6 {
                panning = true
                CGAssociateMouseAndMouseCursorPosition(0)   // hold the cursor still while panning
            }
            if panning {
                let s = config.panSpeed * (config.panInvert ? -1 : 1)
                postFlags = []
                postScroll(.pixel, Int32((dy * s).rounded()), Int32((dx * s).rounded()), continuous: true)
            }
        }
        return nil
    }

    func buttonUp(_ e: CGEvent) -> Unmanaged<CGEvent>? {
        let btn = Int(e.getIntegerValueField(.mouseEventButtonNumber))
        guard let rule = active, btn == activeButton else { return Unmanaged.passUnretained(e) }
        active = nil; activeButton = -1
        if panning {
            panning = false
            CGAssociateMouseAndMouseCursorPosition(1)
            return nil
        }
        if rule.drag == .gestures && hypot(moveX, moveY) > 40 {
            let a: MouseAction
            if abs(moveX) > abs(moveY) { a = moveX > 0 ? rule.right : rule.left }
            else { a = moveY > 0 ? rule.down : rule.up }
            perform(a, button: btn)
        } else {
            perform(rule.click, button: btn)
        }
        return nil
    }

    // MARK: Actions

    func perform(_ a: MouseAction, button: Int) {
        let arrowFlags: CGEventFlags = [.maskControl, .maskSecondaryFn]
        switch a.kind {
        case .none: break
        case .originalClick: postClick(button)
        case .shortcut: if a.keyCode >= 0 { postKey(CGKeyCode(a.keyCode), flags: CGEventFlags(rawValue: a.mods)) }
        case .missionControl:
            let mc = "/System/Applications/Mission Control.app"
            if FileManager.default.fileExists(atPath: mc) { NSWorkspace.shared.open(URL(fileURLWithPath: mc)) }
            else { postKey(126, flags: arrowFlags) }
        case .appExpose: postKey(125, flags: arrowFlags)
        case .spaceLeft: postKey(123, flags: arrowFlags)
        case .spaceRight: postKey(124, flags: arrowFlags)
        case .showDesktop: postKey(103, flags: .maskSecondaryFn)
        case .back: postKey(33, flags: .maskCommand)
        case .forward: postKey(30, flags: .maskCommand)
        case .openRun: openTarget(a.target)
        }
    }

    func postKey(_ code: CGKeyCode, flags: CGEventFlags) {
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let ev = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down) else { continue }
            ev.flags = flags
            ev.setIntegerValueField(.eventSourceUserData, value: magic)
            ev.post(tap: .cghidEventTap)
        }
    }

    func postClick(_ button: Int) {
        let loc = CGEvent(source: nil)?.location ?? .zero
        let b = CGMouseButton(rawValue: UInt32(button)) ?? .center
        for type in [CGEventType.otherMouseDown, .otherMouseUp] {
            guard let ev = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: loc, mouseButton: b) else { continue }
            ev.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button))
            ev.setIntegerValueField(.eventSourceUserData, value: magic)
            ev.post(tap: .cghidEventTap)
        }
    }

    func openTarget(_ raw: String) {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return }
        if t.lowercased().hasPrefix("shortcut:") {
            let name = String(t.dropFirst("shortcut:".count)).trimmingCharacters(in: .whitespaces)
            run("/usr/bin/shortcuts", ["run", name])
        } else if t.contains("://"), let url = URL(string: t) {
            NSWorkspace.shared.open(url)
        } else {
            let path = (t as NSString).expandingTildeInPath
            let ext = (path as NSString).pathExtension.lowercased()
            if ["sh", "command", "zsh", "bash"].contains(ext) { run("/bin/zsh", [path]) }
            else if ext == "py" { run("/usr/bin/env", ["python3", path]) }
            else { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
        }
    }

    func run(_ exe: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        try? p.run()
    }
}

// MARK: - Cursor speed and acceleration (IOKit HID event system)

final class Cursor {
    static let shared = Cursor()
    typealias CreateFn = @convention(c) (CFAllocator?) -> UnsafeMutableRawPointer?
    typealias CopyServicesFn = @convention(c) (UnsafeRawPointer) -> UnsafeRawPointer?
    typealias ConformsFn = @convention(c) (UnsafeRawPointer, UInt32, UInt32) -> UInt8
    typealias SetPropFn = @convention(c) (UnsafeRawPointer, UnsafeRawPointer, UnsafeRawPointer) -> UInt8
    typealias CopyPropFn = @convention(c) (UnsafeRawPointer, UnsafeRawPointer) -> UnsafeRawPointer?

    private var client: UnsafeMutableRawPointer?
    private var copyServices: CopyServicesFn?
    private var conforms: ConformsFn?
    private var setProp: SetPropFn?
    private var copyProp: CopyPropFn?
    private var originalAccel: NSNumber?
    private var originalRes: NSNumber?
    private var overriding = false
    private let accelKey = "HIDMouseAcceleration" as CFString
    private let resKey = "HIDPointerResolution" as CFString

    init() {
        guard let h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW),
              let c = dlsym(h, "IOHIDEventSystemClientCreateSimpleClient"),
              let s = dlsym(h, "IOHIDEventSystemClientCopyServices"),
              let f = dlsym(h, "IOHIDServiceClientConformsTo"),
              let sp = dlsym(h, "IOHIDServiceClientSetProperty"),
              let cp = dlsym(h, "IOHIDServiceClientCopyProperty") else { return }
        let create = unsafeBitCast(c, to: CreateFn.self)
        client = create(kCFAllocatorDefault)
        copyServices = unsafeBitCast(s, to: CopyServicesFn.self)
        conforms = unsafeBitCast(f, to: ConformsFn.self)
        setProp = unsafeBitCast(sp, to: SetPropFn.self)
        copyProp = unsafeBitCast(cp, to: CopyPropFn.self)
    }

    private func mice() -> [UnsafeRawPointer] {
        guard let client = client, let copyServices = copyServices, let conforms = conforms,
              let raw = copyServices(UnsafeRawPointer(client)) else { return [] }
        let arr = Unmanaged<CFArray>.fromOpaque(raw).takeRetainedValue()
        var out: [UnsafeRawPointer] = []
        for i in 0..<CFArrayGetCount(arr) {
            if let s = CFArrayGetValueAtIndex(arr, i), conforms(s, 1, 2) != 0 { out.append(s) }
        }
        return out
    }

    private func read(_ s: UnsafeRawPointer, _ key: CFString) -> NSNumber? {
        guard let copyProp = copyProp else { return nil }
        return withExtendedLifetime(key) {
            guard let p = copyProp(s, Unmanaged.passUnretained(key).toOpaque()) else { return nil }
            return Unmanaged<AnyObject>.fromOpaque(p).takeRetainedValue() as? NSNumber
        }
    }

    private func write(_ s: UnsafeRawPointer, _ key: CFString, _ value: Int) {
        guard let setProp = setProp else { return }
        let n = NSNumber(value: value)
        withExtendedLifetime((key, n)) {
            _ = setProp(s, Unmanaged.passUnretained(key).toOpaque(), Unmanaged.passUnretained(n).toOpaque())
        }
    }

    func apply(_ c: Config) {
        let list = mice()
        if c.cursorOverride {
            if originalAccel == nil, let first = list.first {
                originalAccel = read(first, accelKey)
                originalRes = read(first, resKey)
            }
            // 16.16 fixed point. Negative acceleration means a straight 1:1 curve.
            let accel = c.disableAccel ? -65536 : Int(c.cursorAccel * 65536)
            let res = Int(400.0 / max(c.cursorSpeed, 0.1) * 65536)
            for s in list { write(s, accelKey, accel); write(s, resKey, res) }
            overriding = true
        } else if overriding {
            restore()
        }
    }

    func restore() {
        guard overriding else { return }
        for s in mice() {
            write(s, accelKey, originalAccel?.intValue ?? 45056)
            write(s, resKey, originalRes?.intValue ?? (400 << 16))
        }
        overriding = false
    }
}

// MARK: - Settings UI

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let fmt: String
    var body: some View {
        HStack {
            Text(title)
            Slider(value: $value, in: range)
            Text(String(format: fmt, value)).monospacedDigit().frame(width: 56, alignment: .trailing)
        }
    }
}

final class KeyRecorder {
    private var monitor: Any?
    func record(_ done: @escaping (NSEvent) -> Void) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] ev in
            done(ev)
            self?.stop()
            return nil
        }
    }
    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
    }
}

struct ActionRow: View {
    let title: String
    @Binding var action: MouseAction
    @State private var recording = false
    @State private var recorder = KeyRecorder()

    var body: some View {
        HStack {
            Text(title).frame(width: 90, alignment: .leading)
            Picker("", selection: $action.kind) {
                ForEach(ActionKind.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .frame(width: 190)
            if action.kind == .shortcut {
                Button(recording ? "Press keys…" : shortcutName(action)) {
                    recording = true
                    recorder.record { ev in
                        action.keyCode = Int(ev.keyCode)
                        action.mods = UInt64(ev.modifierFlags.intersection([.command, .option, .control, .shift]).rawValue)
                        recording = false
                    }
                }
            }
            if action.kind == .openRun {
                TextField("Web link, file, app, script, or shortcut:Name", text: $action.target)
            }
            Spacer(minLength: 0)
        }
    }
}

struct RuleCard: View {
    @Binding var rule: ButtonRule
    let onDelete: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(buttonName(rule.button)).font(.headline)
                    Spacer()
                    Text("Only while holding").foregroundColor(.secondary).font(.caption)
                    Toggle("⌃", isOn: $rule.ctrl).toggleStyle(.button)
                    Toggle("⌥", isOn: $rule.opt).toggleStyle(.button)
                    Toggle("⇧", isOn: $rule.shift).toggleStyle(.button)
                    Toggle("⌘", isOn: $rule.cmd).toggleStyle(.button)
                    Button(action: onDelete) { Image(systemName: "trash") }.buttonStyle(.borderless)
                }
                ActionRow(title: "Click", action: $rule.click)
                HStack {
                    Text("Hold and drag").frame(width: 90, alignment: .leading)
                    Picker("", selection: $rule.drag) {
                        ForEach(DragMode.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 260)
                    Spacer(minLength: 0)
                }
                if rule.drag == .gestures {
                    ActionRow(title: "  Drag up", action: $rule.up)
                    ActionRow(title: "  Drag down", action: $rule.down)
                    ActionRow(title: "  Drag left", action: $rule.left)
                    ActionRow(title: "  Drag right", action: $rule.right)
                }
            }
            .padding(6)
        }
    }
}

struct ScrollTab: View {
    @ObservedObject var store = Store.shared
    var body: some View {
        Form {
            Section("Mouse wheel") {
                Toggle("Smooth scrolling", isOn: $store.config.smooth)
                if store.config.smooth {
                    SliderRow(title: "Distance per notch", value: $store.config.scrollSpeed, range: 0.3...4, fmt: "%.1f×")
                    SliderRow(title: "Glide time", value: $store.config.scrollDuration, range: 0.05...0.8, fmt: "%.2f s")
                    SliderRow(title: "Acceleration", value: $store.config.scrollAccel, range: 0...3, fmt: "%.1f")
                } else {
                    Stepper("Lines per notch: \(store.config.discreteLines)", value: $store.config.discreteLines, in: 1...15)
                    Toggle("Speed up when spinning fast", isOn: $store.config.discreteAccel)
                }
                Toggle("Reverse vertical direction", isOn: $store.config.reverseV)
                Toggle("Reverse horizontal direction", isOn: $store.config.reverseH)
            }
            Section("While holding a key and scrolling") {
                modPicker("⌘ Command", $store.config.cmdScroll)
                modPicker("⌥ Option", $store.config.optScroll)
                modPicker("⌃ Control", $store.config.ctrlScroll)
                modPicker("⇧ Shift", $store.config.shiftScroll)
            }
            Section {
                Text("Trackpads and Magic Mouse already scroll smoothly, so Wheelhouse leaves them alone.")
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    func modPicker(_ title: String, _ sel: Binding<ModAction>) -> some View {
        Picker(title, selection: sel) {
            ForEach(ModAction.allCases) { Text($0.label).tag($0) }
        }
    }
}

struct CursorTab: View {
    @ObservedObject var store = Store.shared
    var body: some View {
        Form {
            Section {
                Toggle("Let Wheelhouse set cursor speed", isOn: $store.config.cursorOverride)
                Group {
                    Toggle("Turn off acceleration (same hand movement = same cursor distance)", isOn: $store.config.disableAccel)
                    SliderRow(title: "Speed", value: $store.config.cursorSpeed, range: 0.2...4, fmt: "%.1f×")
                    if !store.config.disableAccel {
                        SliderRow(title: "Acceleration", value: $store.config.cursorAccel, range: 0...3, fmt: "%.1f")
                    }
                }
                .disabled(!store.config.cursorOverride)
            } footer: {
                Text("When this is off, the speed in System Settings › Mouse is used. Changes apply to every connected mouse.")
                    .foregroundColor(.secondary)
            }
            Section("Report rate") {
                HStack {
                    Text("\(store.rate) Hz").font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
                    Spacer()
                    Text("Move the mouse in circles to measure how often it reports.").foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct ButtonsTab: View {
    @ObservedObject var store = Store.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach($store.config.buttons) { $rule in
                        let id = rule.id
                        RuleCard(rule: $rule) { store.config.buttons.removeAll { $0.id == id } }
                    }
                }
                .padding(.vertical, 4)
            }
            HStack {
                Menu("Add a button") {
                    ForEach(2..<10, id: \.self) { b in
                        Button(buttonName(b)) {
                            var r = ButtonRule(); r.button = b
                            store.config.buttons.append(r)
                        }
                    }
                }
                .fixedSize()
                Spacer()
                Text("Drag-to-scroll speed")
                Slider(value: $store.config.panSpeed, in: 0.5...5).frame(width: 110)
                Toggle("Reverse", isOn: $store.config.panInvert)
            }
            Text("Left and right click are never changed. The same button can have several rules with different held keys.")
                .font(.caption).foregroundColor(.secondary)
        }
        .padding()
    }
}

struct RunningApp: Hashable { let id: String; let name: String }

struct AppsTab: View {
    @ObservedObject var store = Store.shared

    var running: [RunningApp] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { a in a.bundleIdentifier.map { RunningApp(id: $0, name: a.localizedName ?? $0) } }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Exception apps: Wheelhouse steps aside for these apps while they are in front (handy for games, or apps with their own scrolling).")
                .foregroundColor(.secondary)
            List {
                ForEach($store.config.exceptions) { $ex in
                    let id = ex.id
                    HStack {
                        appIcon(ex.bundleID)
                        Text(ex.name)
                        Spacer()
                        Toggle("Skip scrolling", isOn: $ex.noScroll)
                        Toggle("Skip buttons", isOn: $ex.noButtons)
                        Button { store.config.exceptions.removeAll { $0.id == id } } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
            }
            HStack {
                Menu("Add a running app") {
                    ForEach(running, id: \.self) { a in Button(a.name) { add(a.id, a.name) } }
                }
                .fixedSize()
                Button("Choose app…") { chooseApp() }
                Spacer()
            }
        }
        .padding()
    }

    func add(_ id: String, _ name: String) {
        if store.config.exceptions.contains(where: { $0.bundleID == id }) { return }
        store.config.exceptions.append(AppException(bundleID: id, name: name))
    }

    func chooseApp() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.application]
        p.directoryURL = URL(fileURLWithPath: "/Applications")
        if p.runModal() == .OK, let url = p.url, let b = Bundle(url: url), let id = b.bundleIdentifier {
            add(id, url.deletingPathExtension().lastPathComponent)
        }
    }

    func appIcon(_ id: String) -> some View {
        let img: NSImage
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            img = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            img = NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
        }
        return Image(nsImage: img).resizable().frame(width: 18, height: 18)
    }
}

struct KeyButton: View {
    @Binding var code: Int
    @State private var recording = false
    @State private var recorder = KeyRecorder()
    var body: some View {
        Button(recording ? "Press a key…" : (code < 0 ? "Pick a key" : keyName(code))) {
            recording = true
            recorder.record { ev in code = Int(ev.keyCode); recording = false }
        }
        .frame(minWidth: 120)
    }
}

struct KeysTab: View {
    @ObservedObject var store = Store.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Key swaps: pressing the first key types the second one instead, in every app. Modifier keys like ⌘ can't be swapped here.")
                .foregroundColor(.secondary)
            List {
                ForEach($store.config.keySwaps) { $s in
                    let id = s.id
                    HStack {
                        KeyButton(code: $s.from)
                        Image(systemName: "arrow.right")
                        KeyButton(code: $s.to)
                        Spacer()
                        Button { store.config.keySwaps.removeAll { $0.id == id } } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
            }
            Button("Add a key swap") { store.config.keySwaps.append(KeySwap()) }
            Text("To fire a shortcut from a mouse button, use the Buttons tab.").font(.caption).foregroundColor(.secondary)
        }
        .padding()
    }
}

struct GeneralTab: View {
    @ObservedObject var store = Store.shared

    var loginBinding: Binding<Bool> {
        Binding(get: { _ = store.loginTick; return SMAppService.mainApp.status == .enabled },
                set: { on in
                    do {
                        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch {
                        let a = NSAlert(); a.messageText = "Couldn't change Start at login"
                        a.informativeText = error.localizedDescription + "\n\nMove Wheelhouse into Applications and try again."
                        a.runModal()
                    }
                    store.loginTick += 1
                })
    }

    var body: some View {
        Form {
            Section {
                Toggle("Wheelhouse is on", isOn: $store.config.enabled)
                Toggle("Start at login", isOn: loginBinding)
                Toggle("Hide menu bar icon", isOn: $store.config.hideIcon)
                if store.config.hideIcon {
                    Text("To come back here, open Wheelhouse again from your Applications folder.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            Section("Permission") {
                HStack {
                    Image(systemName: store.trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(store.trusted ? .green : .orange)
                    Text(store.trusted ? "Accessibility access is on." : "Accessibility access is needed.")
                    Spacer()
                    Button("Open Accessibility settings") { openAccessibility() }
                }
            }
            Section("Settings file") {
                HStack {
                    Button("Export…") { exportConfig() }
                    Button("Import…") { importConfig() }
                    Spacer()
                    Button("Reset everything") { reset() }
                }
                Text("Importing replaces all current settings.").font(.caption).foregroundColor(.secondary)
            }
            Section {
                Text("Wheelhouse 1.0. No network access, no drivers, nothing installed in the background. To uninstall, quit it and drag it to the Trash.")
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    func exportConfig() {
        let p = NSSavePanel()
        p.allowedContentTypes = [.json]
        p.nameFieldStringValue = "Wheelhouse Settings.json"
        guard p.runModal() == .OK, let url = p.url else { return }
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(store.config) { try? data.write(to: url) }
    }

    func importConfig() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.json]
        guard p.runModal() == .OK, let url = p.url else { return }
        if let data = try? Data(contentsOf: url), let c = try? JSONDecoder().decode(Config.self, from: data) {
            store.config = c
        } else {
            let a = NSAlert(); a.messageText = "That file isn't a Wheelhouse settings file."; a.runModal()
        }
    }

    func reset() {
        let a = NSAlert()
        a.messageText = "Reset all Wheelhouse settings?"
        a.informativeText = "Buttons, exception apps and key swaps go back to the defaults."
        a.addButton(withTitle: "Reset")
        a.addButton(withTitle: "Cancel")
        if a.runModal() == .alertFirstButtonReturn { store.config = Config() }
    }
}

func openAccessibility() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
        NSWorkspace.shared.open(url)
    }
}

struct SettingsView: View {
    @ObservedObject var store = Store.shared
    var body: some View {
        VStack(spacing: 0) {
            if !store.trusted {
                HStack {
                    Image(systemName: "hand.raised.fill")
                    Text("Wheelhouse needs Accessibility access to see your mouse. Turn it on in System Settings, then it starts by itself.")
                    Spacer()
                    Button("Open settings") { openAccessibility() }
                }
                .padding(10)
                .background(Color.orange.opacity(0.18))
            }
            TabView {
                ScrollTab().tabItem { Label("Scrolling", systemImage: "scroll") }
                CursorTab().tabItem { Label("Cursor", systemImage: "cursorarrow.motionlines") }
                ButtonsTab().tabItem { Label("Buttons", systemImage: "computermouse") }
                AppsTab().tabItem { Label("Apps", systemImage: "square.grid.2x2") }
                KeysTab().tabItem { Label("Keys", systemImage: "keyboard") }
                GeneralTab().tabItem { Label("General", systemImage: "gearshape") }
            }
            .padding(12)
        }
        .frame(width: 680, height: 600)
    }
}

// MARK: - App delegate, menu bar

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var status: NSStatusItem!
    var window: NSWindow?
    var enabledItem = NSMenuItem()
    var smoothItem = NSMenuItem()
    var rateItem = NSMenuItem()
    var retryTimer: Timer?

    func applicationDidFinishLaunching(_ note: Notification) {
        buildMainMenu()
        let store = Store.shared
        Engine.shared.config = store.config
        store.onChange = { [weak self] in
            Engine.shared.config = Store.shared.config
            Cursor.shared.apply(Store.shared.config)
            self?.refresh()
        }

        Engine.shared.frontBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil, queue: .main) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Engine.shared.frontBundle = app?.bundleIdentifier ?? ""
        }

        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let img = NSImage(systemSymbolName: "computermouse", accessibilityDescription: "Wheelhouse") {
            img.isTemplate = true
            status.button?.image = img
        } else {
            status.button?.title = "W"
        }
        let menu = NSMenu()
        menu.delegate = self
        enabledItem = NSMenuItem(title: "Wheelhouse is on", action: #selector(toggleEnabled), keyEquivalent: "")
        smoothItem = NSMenuItem(title: "Smooth scrolling", action: #selector(toggleSmooth), keyEquivalent: "")
        rateItem = NSMenuItem(title: "Report rate: –", action: nil, keyEquivalent: "")
        rateItem.isEnabled = false
        for i in [enabledItem, smoothItem] { i.target = self; menu.addItem(i) }
        menu.addItem(.separator())
        menu.addItem(rateItem)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(NSMenuItem(title: "Quit Wheelhouse", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        status.menu = menu
        refresh()

        Cursor.shared.apply(store.config)
        startTap()

        // Report rate, once a second.
        let rateTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            let n = Engine.shared.moveCount
            Engine.shared.moveCount = 0
            if Store.shared.rate != n { Store.shared.rate = n }
            self?.rateItem.title = "Report rate: \(n) Hz"
        }
        RunLoop.main.add(rateTimer, forMode: .common)

        // Re-apply cursor settings so newly connected mice pick them up.
        let cursorTimer = Timer(timeInterval: 5, repeats: true) { _ in
            if Store.shared.config.cursorOverride { Cursor.shared.apply(Store.shared.config) }
        }
        RunLoop.main.add(cursorTimer, forMode: .common)

        if !UserDefaults.standard.bool(forKey: "WheelhouseLaunchedBefore") {
            UserDefaults.standard.set(true, forKey: "WheelhouseLaunchedBefore")
            showSettings()
        }
    }

    func startTap() {
        if Engine.shared.start() {
            Store.shared.trusted = true
            return
        }
        Store.shared.trusted = false
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        showSettings()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
            if Engine.shared.start() {
                Store.shared.trusted = true
                t.invalidate()
                self?.retryTimer = nil
            }
        }
    }

    func refresh() {
        let c = Store.shared.config
        enabledItem.state = c.enabled ? .on : .off
        smoothItem.state = c.smooth ? .on : .off
        status?.button?.appearsDisabled = !c.enabled
        status?.isVisible = !c.hideIcon
    }

    func menuWillOpen(_ menu: NSMenu) { refresh() }

    @objc func toggleEnabled() { Store.shared.config.enabled.toggle() }
    @objc func toggleSmooth() { Store.shared.config.smooth.toggle() }

    @objc func showSettings() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.title = "Wheelhouse"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        CGAssociateMouseAndMouseCursorPosition(1)
        Cursor.shared.restore()
    }

    // An app menu with Edit commands so copy and paste work in text fields.
    func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit Wheelhouse", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        edit.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = edit
        let winItem = NSMenuItem(); main.addItem(winItem)
        let win = NSMenu(title: "Window")
        win.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        winItem.submenu = win
        NSApp.mainMenu = main
    }
}

// MARK: - Entry point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
