import SwiftUI
import AppKit

/// Every setting in one place. Shown in the Library's Settings tab and in the Settings window, so it's
/// reachable even when the menu bar icon is hidden behind the notch.
struct SettingsForm: View {
    let model: PlayerModel
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        Form {
            Section("Where it lives") {
                Picker("Show as", selection: $prefs.displayMode) {
                    ForEach(DisplayMode.allCases) { Text($0.rawValue).tag($0) }
                }
                Text(prefs.displayMode.blurb).font(.caption).foregroundStyle(.secondary)
                if prefs.displayMode == .desktop {
                    Picker("Size", selection: $prefs.playerSize) {
                        ForEach(PlayerSize.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Float above other windows", isOn: $prefs.floatAboveWindows)
                    Button("Move the turntable to the top right") {
                        (NSApp.delegate as? AppDelegate)?.panel.resetPosition()
                    }
                }
                Toggle("Open at login", isOn: Binding(get: { prefs.launchAtLogin }, set: { prefs.launchAtLogin = $0 }))
            }

            Section("Music") {
                Picker("Follow", selection: $prefs.musicSource) {
                    ForEach(MusicSource.allCases) { Text($0.rawValue).tag($0) }
                }
                TimelineView(.periodic(from: .now, by: 2)) { _ in
                    HStack {
                        Text(model.service.status).font(.caption).foregroundStyle(.secondary)
                        if model.service.needsPermission {
                            Button("Allow…") { model.service.openPermissionSettings() }
                        }
                    }
                }
            }

            Section("Turntable") {
                Toggle("Pet operates the tonearm", isOn: $prefs.petOperatesArm)
                Toggle("Tonearm follows the groove", isOn: $prefs.armFollowsGroove)
                Toggle("Needle drop and crackle", isOn: $prefs.sound)
                Picker("Spin-up", selection: $prefs.drive) {
                    ForEach(DriveChoice.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Appearance", selection: $prefs.theme) {
                    ForEach(ThemeChoice.allCases) { Text($0.rawValue).tag($0) }
                }
            }

            Section("Pet") {
                Toggle("Show the pet", isOn: $prefs.showPet)
                Picker("Pet", selection: Binding(get: { model.pet }, set: { model.selectPet($0) })) {
                    ForEach(Array(PetSpec.all.enumerated()), id: \.offset) { i, p in Text(p.name).tag(i) }
                }
                Toggle("Headphones", isOn: Binding(get: { model.wearPhones }, set: { _ in model.toggleHeadphones() }))
                Toggle("Sunglasses", isOn: Binding(get: { model.wearShades }, set: { _ in model.toggleSunglasses() }))
                Toggle("Scarf in the album's colour", isOn: Binding(get: { model.wearScarf }, set: { _ in model.toggleScarf() }))
            }

            Section("Colours") {
                Picker("Theme", selection: Binding(
                    get: { PlayerStyle.presets.firstIndex(where: { $0.style == prefs.style }) ?? -1 },
                    set: { i in
                        guard PlayerStyle.presets.indices.contains(i) else { return }
                        prefs.style = PlayerStyle.presets[i].style
                        model.selectVinyl(prefs.style.vinyl == nil ? 0 : VinylStyle.customIndex)
                    })) {
                    ForEach(Array(PlayerStyle.presets.enumerated()), id: \.offset) { i, p in Text(p.name).tag(i) }
                    if !PlayerStyle.presets.contains(where: { $0.style == prefs.style }) { Text("Custom").tag(-1) }
                }
                color("Accent", \.accent, Tokens.accent)
                DisclosureGroup("Fine-tune colours") {
                    color("Deck", \.deck, Tokens.sandTop)
                    color("Record", \.vinyl, RGB(hex: "#101012"))
                    color("Label ring", \.ring, Tokens.labelRing)
                    color("Card", \.card, RGB(hex: "#1e1e22"))
                    color("Pet", \.pet, PetSpec.at(model.pet).palette["o"] ?? .white)
                    Button("Reset all colours") { prefs.style = PlayerStyle(); model.selectVinyl(0) }
                }
            }

            Section("Keyboard shortcuts") {
                Toggle("Control the music from anywhere", isOn: $prefs.hotKeys)
                ForEach(HotKeys.shortcuts, id: \.id) { s in
                    Text(s.label).font(.callout.monospaced()).foregroundStyle(.secondary)
                }
            }

            Section("Friends") {
                Toggle("Show friends what I'm listening to", isOn: $prefs.shareListening)
                Text("Friends see the song on your turntable in their Friends list and can listen along.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Sharing") {
                TextField("Your name", text: $prefs.senderName, prompt: Text("A friend"))
                TextField("Shared record page", text: $prefs.shareBaseURL)
                Text("Where share links open for people without the app. Host the web folder (e.g. on Vercel) and paste its shared-record address here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Show the welcome screen again") {
                    WelcomeWindowController.shared.show(model: model)
                }
                Button("Quit Vinyl Player", role: .destructive) { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
    }

    private func color(_ title: String, _ key: WritableKeyPath<PlayerStyle, RGB?>, _ fallback: RGB) -> some View {
        HStack {
            ColorPicker(title, selection: Binding(
                get: { (prefs.style[keyPath: key] ?? fallback).color },
                set: { c in
                    guard let rgb = RGB(color: c) else { return }
                    prefs.style[keyPath: key] = RGB(rgb.r, rgb.g, rgb.b)
                    if key == \PlayerStyle.vinyl { model.selectVinyl(VinylStyle.customIndex) }
                }), supportsOpacity: false)
            if prefs.style[keyPath: key] != nil {
                Button("Default") { prefs.style[keyPath: key] = nil }
                    .buttonStyle(.borderless)
            }
        }
    }
}
