// muguet - Launcher.swift
// Constantin Clerc (c22dev) - 0.1

import SwiftUI
import UIKit
import UniformTypeIdentifiers

let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
let configURL = documentsURL.appendingPathComponent("config.json")

// The game reads saves from <Documents>/saves/userdata/... (see src/config.rs on iOS).
let savesRoot = documentsURL.appendingPathComponent("saves")
let defaultTitle = "GTA V"

/// Slot number encoded in an SGTA5xxxx file name, or nil if it isn't one.
func saveSlot(of name: String) -> Int? {
    guard name.hasPrefix("SGTA5") else { return nil }
    let digits = name.dropFirst(5)
    guard digits.count == 4, digits.allSatisfy(\.isNumber) else { return nil }
    return Int(digits)
}

final class SaveImporter: ObservableObject {
    @Published var title = defaultTitle
    @Published var status: String?
    @Published var statusIsError = false

    // No path separators or reserved characters, and never "..".
    func validTitle(_ t: String) -> Bool {
        let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.contains("..") && trimmed.rangeOfCharacter(from: CharacterSet(charactersIn: "\\/:*?\"<>|")) == nil
    }

    func importSave(_ source: URL) {
        let fm = FileManager.default
        let name = source.lastPathComponent
        statusIsError = false
        guard saveSlot(of: name) != nil else { return fail("That doesn't look like a save file (SGTA5xxxx).") }
        guard validTitle(title) else { return fail("Check the title folder.") }

        let dir = savesRoot
            .appendingPathComponent("userdata/Documents/Rockstar Games")
            .appendingPathComponent(trimmedTitle)
            .appendingPathComponent("Default")
        let dest = dir.appendingPathComponent(name)
        if source.standardizedFileURL == dest.standardizedFileURL {
            return fail("That file is already the active save.")
        }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        var backup: URL?
        var installed = false
        do {
            // The file the user picked lives outside our sandbox, so copy it in first.
            let staged = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            defer { try? fm.removeItem(at: staged) }
            if fm.fileExists(atPath: staged.path) { try fm.removeItem(at: staged) }
            try fm.copyItem(at: source, to: staged)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            // Keep whatever was in this slot before overwriting it. The backup goes
            // outside /userdata so the game never sees it next to the real saves.
            if fm.fileExists(atPath: dest.path) {
                let b = backupURL(for: dest, title: trimmedTitle)
                try fm.copyItem(at: dest, to: b)
                backup = b
                try fm.removeItem(at: dest)
            }
            try fm.copyItem(at: staged, to: dest)
            installed = true
            let slot = saveSlot(of: name) ?? 0
            status = "Imported \(name)."
                + (backup == nil ? "" : " Previous save backed up.")
                + (newerSlotNotice(in: dir, than: slot) ?? "")
        } catch {
            // copyItem is not atomic, so a half-written file may be sitting at dest.
            // Drop it and put the previous save back rather than leaving a corrupt one.
            if !installed {
                try? fm.removeItem(at: dest)
                if let b = backup { try? fm.copyItem(at: b, to: dest) }
            }
            fail("Could not import save: \(error.localizedDescription)")
        }
    }

    /// The game loads the newest slot, so say so when a later one will win.
    private func newerSlotNotice(in dir: URL, than slot: Int) -> String? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        guard let newest = names.compactMap({ saveSlot(of: $0) }).filter({ $0 > slot }).max() else { return nil }
        return " SGTA5\(String(format: "%04d", newest)) is newer and will be loaded instead."
    }

    private func fail(_ message: String) {
        status = message
        statusIsError = true
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// A timestamped copy of the slot we are about to overwrite, kept outside the
    /// directory the game scans so it can never be mistaken for a real save.
    private func backupURL(for dest: URL, title: String) -> URL {
        let dir = savesRoot.appendingPathComponent("save-backups").appendingPathComponent(title)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let name = "\(dest.lastPathComponent).\(stamp)"
        var url = dir.appendingPathComponent("\(name).bak")
        // Two imports in the same second must not clobber each other's backup.
        if FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(name)-\(UUID().uuidString.prefix(4)).bak")
        }
        return url
    }
}

final class Settings: ObservableObject {
    @Published var mode = 2
    @Published var scale = 0.5
    @Published var fps = 60
    @Published var textures = 0
    @Published var touch = 1.0
    @Published var mute = false
    @Published var showFps = false
    @Published var multiplayer = false
    @Published var host = false
    @Published var server = ""
    @Published var name = UIDevice.current.name
    var extra: [String: Any] = [:]

    init() {
        guard let data = try? Data(contentsOf: configURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        extra = json
        if let v = json["start_mode"] as? Int, (1...2).contains(v) { mode = v }
        if let v = json["scale"] as? Double { scale = v }
        if let v = json["fps_limit"] as? Int { fps = v == 30 ? 30 : 60 }
        if let v = json["texture_quality"] as? Int, (0...2).contains(v) { textures = v }
        if let v = json["touch_sensitivity"] as? Double { touch = v }
        if let v = json["mute"] as? Bool { mute = v }
        if let v = json["show_fps"] as? Bool { showFps = v }
        if let v = json["multiplayer"] as? Bool { multiplayer = v }
        if let v = json["host"] as? Bool { host = v }
        if let v = json["server"] as? String { server = v }
        if let v = json["player_name"] as? String, !v.isEmpty { name = v }
    }

    func save() throws {
        var json = extra
        json["start_mode"] = mode
        json["scale"] = scale
        json["fps_limit"] = fps
        json["texture_quality"] = textures
        json["touch_sensitivity"] = (touch * 100).rounded() / 100
        json["mute"] = mute
        json["show_fps"] = showFps
        json["multiplayer"] = multiplayer
        json["host"] = host
        json["server"] = server.trimmingCharacters(in: .whitespaces)
        json["player_name"] = name.trimmingCharacters(in: .whitespaces)
        if json["extra_args"] == nil { json["extra_args"] = [String]() }
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: configURL)
    }
}

@_silgen_name("muguet_import")
func muguet_import(_ zip: UnsafePointer<CChar>, _ progress: @convention(c) (UInt64, UInt64) -> Void) -> Bool
@_silgen_name("muguet_import_error")
func muguet_import_error() -> UnsafePointer<CChar>?
@_silgen_name("muguet_game_ready")
func muguet_game_ready() -> Bool
@_silgen_name("muguet_has_game_code")
func muguet_has_game_code() -> Bool

final class Importer: ObservableObject {
    static let shared = Importer()
    @Published var ready = muguet_game_ready()
    @Published var progress: Double?
    @Published var error: String?
    @Published var local: [URL] = []

    func scan() {
        let docs = configURL.deletingLastPathComponent()
        let files = (try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: [.isRegularFileKey], options: .skipsHiddenFiles)) ?? []
        local = files.filter { $0.pathExtension.lowercased() == "zip" && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func run(_ url: URL) {
        error = nil
        progress = 0
        DispatchQueue.global(qos: .userInitiated).async {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let ok = url.path.withCString { muguet_import($0) { done, total in
                let p = total > 0 ? Double(done) / Double(total) : 0
                DispatchQueue.main.async { Importer.shared.progress = p }
            } }
            let message = ok ? nil : muguet_import_error().map { String(cString: $0) } ?? "unknown error"
            DispatchQueue.main.async {
                self.progress = nil
                self.ready = muguet_game_ready()
                if let message { self.error = "Import failed: \(message)" }
            }
        }
    }
}

struct LauncherView: View {
    @StateObject private var s = Settings()
    @StateObject private var save = SaveImporter()
    @ObservedObject private var importer = Importer.shared
    @State private var error: String?
    @State private var picking = false
    @State private var pickingSave = false
    @Environment(\.scenePhase) private var phase
    let play: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 16) {
                Text("Muguet").font(.largeTitle.weight(.bold))
                if !muguet_has_game_code() {
                    Text("This build has no game code: build it with ./make-ios.sh <game.zip>.")
                        .foregroundStyle(.red).font(.callout).multilineTextAlignment(.center)
                } else if !importer.ready || importer.progress != nil {
                    importView
                } else {
                    if let error { Text(error).foregroundStyle(.red).font(.callout).multilineTextAlignment(.center) }
                    playButton
                    Button("Import other game data…") { picking = true }.font(.caption)
                }
                Text("proudly made by c22dev").font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            Form {
                Picker("Mode", selection: $s.mode) {
                    Text("Story Mode").tag(1)
                    Text("Sandbox").tag(2)
                }
                Picker("Resolution", selection: $s.scale) {
                    Text("35 % (fastest)").tag(0.35)
                    Text("50 %").tag(0.5)
                    Text("75 %").tag(0.75)
                    Text("100 % (sharpest)").tag(1.0)
                }
                Picker("Textures", selection: $s.textures) {
                    Text("Normal (less memory)").tag(0)
                    Text("High").tag(1)
                    Text("Very High").tag(2)
                }
                Picker("Frame limit", selection: $s.fps) {
                    Text("30 fps (cooler)").tag(30)
                    Text("60 fps").tag(60)
                }
                HStack {
                    Text("Look sensitivity")
                    Slider(value: $s.touch, in: 0.25...3, step: 0.25)
                    Text(String(format: "%.2f×", s.touch)).monospacedDigit().frame(width: 50, alignment: .trailing)
                }
                Toggle("Mute audio", isOn: $s.mute)
                Toggle("Show frame rate", isOn: $s.showFps)
                Section("Multiplayer") {
                    Toggle("Play with friends", isOn: $s.multiplayer)
                    if s.multiplayer {
                        TextField("Your name", text: $s.name)
                        Picker("Session", selection: $s.host) {
                            Text("Join").tag(false)
                            Text("Host").tag(true)
                        }
                        .pickerStyle(.segmented)
                        if s.host {
                            Text("Friends join with: \(localIPs().joined(separator: " or "))")
                                .font(.callout).textSelection(.enabled)
                        } else {
                            TextField("Host address", text: $s.server, prompt: Text("192.168.1.20"))
                                .keyboardType(.numbersAndPunctuation)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                    }
                }
                Section("Load custom save") {
                    TextField("Title folder", text: $save.title)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                    Button("Import save…") { pickingSave = true }
                    Text("Your current save is kept in the saves/save-backups folder.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let st = save.status {
                        Text(st).font(.caption).foregroundStyle(save.statusIsError ? Color.red : Color.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .preferredColorScheme(.dark)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.zip]) { result in
            if case .success(let url) = result { importer.run(url) }
        }
        .fileImporter(isPresented: $pickingSave, allowedContentTypes: [.item]) { result in
            if case .success(let url) = result { save.importSave(url) }
        }
        .onAppear { importer.scan() }
        .onChange(of: phase) { p in if p == .active { importer.scan() } }
    }

    @ViewBuilder var importView: some View {
        VStack(spacing: 12) {
            if let p = importer.progress {
                ProgressView(value: p)
                Text("Importing… \(Int(p * 100)) %").font(.callout).monospacedDigit()
            } else {
                Button("Import game data .zip") { picking = true }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                ForEach(importer.local, id: \.self) { url in
                    Button("Import \(url.lastPathComponent)") { importer.run(url) }
                }
                Text("If the picker doesn't work, move the zip to Files → On My iPhone → Muguet and it will show up here.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            if let e = importer.error { Text(e).foregroundStyle(.red).font(.callout).multilineTextAlignment(.center) }
        }
    }

    @ViewBuilder var playButton: some View {
        let button = Button(action: start) {
            Text("Play").font(.title3.weight(.semibold)).frame(maxWidth: 220)
        }
        .controlSize(.large)
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            button.buttonStyle(.glassProminent)
        } else {
            button.buttonStyle(.borderedProminent)
        }
        #else
        button.buttonStyle(.borderedProminent)
        #endif
    }

    func start() {
        if s.multiplayer && !s.host && s.server.trimmingCharacters(in: .whitespaces).isEmpty {
            error = "Enter the host's address to join."
            return
        }
        do { try s.save() } catch { self.error = "Could not save settings: \(error.localizedDescription)"; return }
        play()
    }
}

func localIPs() -> [String] {
    var out: [String] = []
    var ifs: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifs) == 0, let first = ifs else { return ["?"] }
    defer { freeifaddrs(ifs) }
    for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
        guard let a = p.pointee.ifa_addr, a.pointee.sa_family == UInt8(AF_INET) else { continue }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        if getnameinfo(a, socklen_t(a.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
            let ip = String(cString: host)
            if !ip.hasPrefix("127.") && !out.contains(ip) { out.append(ip) }
        }
    }
    return out.isEmpty ? ["?"] : out
}

@_cdecl("muguet_show_launcher")
public func muguetShowLauncher(_ viewController: UnsafeMutableRawPointer, _ done: @convention(c) () -> Void) {
    let parent = Unmanaged<UIViewController>.fromOpaque(viewController).takeUnretainedValue()
    weak var sheet: UIViewController?
    let host = UIHostingController(rootView: LauncherView(play: {
        sheet?.dismiss(animated: true)
        done()
    }))
    sheet = host
    host.modalPresentationStyle = .fullScreen
    host.isModalInPresentation = true
    parent.present(host, animated: false)
}
