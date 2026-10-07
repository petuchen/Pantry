import AppKit
import PantryCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var newFolderService: ModelService = .llamaCpp
    @AppStorage(Prefs.showMenuBar) private var showMenuBar = true
    @AppStorage(Prefs.showSizeInMenuBar) private var showSizeInMenuBar = true
    @AppStorage(Prefs.showInDock) private var showInDock = true

    var body: some View {
        Form {
            Section("Where Pantry looks") {
                ForEach(model.scannedFolders.isEmpty ? defaultFolders : model.scannedFolders) { folder in
                    HStack(spacing: 10) {
                        Image(systemName: folder.exists ? "checkmark.circle.fill" : "minus.circle")
                            .foregroundStyle(folder.exists ? Color.green : Color.secondary)
                            .accessibilityLabel(folder.exists ? "Found" : "Not found")
                        Text(folder.service.displayName).frame(width: 100, alignment: .leading)
                        Text(folder.url.path)
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        if folder.exists {
                            Button("Reveal") { Finder.reveal(folder.url) }.buttonStyle(.borderless)
                        }
                    }
                }
                Text("Defaults follow each tool's own settings, such as OLLAMA_MODELS, HF_HOME and LLAMA_CACHE.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Your own folders") {
                if model.customFolders.isEmpty {
                    Text("Keep models somewhere else, like an external drive, or use another tool such as LM Studio? Add that folder here and pick “Other” if it isn’t one of the listed services.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.customFolders) { folder in
                    HStack {
                        Label(folder.service.displayName, systemImage: folder.service.symbolName).frame(width: 130, alignment: .leading)
                        Text(folder.path).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button {
                            model.customFolders.removeAll { $0.id == folder.id }
                            Task { await model.refresh() }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Stop looking in this folder (files stay where they are)")
                    }
                }
                HStack {
                    Picker("Folder holds", selection: $newFolderService) {
                        ForEach(ModelService.allCases) { Text($0.displayName).tag($0) }
                    }
                    .frame(maxWidth: 260)
                    Button("Add Folder…", action: addFolder)
                }
            }

            Section("Menu bar") {
                Toggle("Show Pantry in the menu bar", isOn: $showMenuBar)
                Toggle("Show total size next to the icon", isOn: $showSizeInMenuBar)
                    .disabled(!showMenuBar)
                Toggle("Show Pantry in the Dock", isOn: $showInDock)
                    .disabled(!showMenuBar)
                Text("Turn the Dock icon off to run Pantry quietly from the menu bar. Closing the window keeps it running; use Quit in the menu bar to exit.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Hugging Face") {
                Label(
                    model.hasHuggingFaceToken ? "Signed in. Private and gated models can be downloaded." : "Not signed in. Public models work; gated ones need a token.",
                    systemImage: model.hasHuggingFaceToken ? "checkmark.circle.fill" : "info.circle"
                )
                Text("Pantry reads the token the Hugging Face CLI saves. Run “hf auth login” in Terminal once; Pantry never stores your token.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 640, height: 640)
        .onChange(of: showMenuBar) { _, isOn in
            // Turning the menu bar item off must never leave the app unreachable.
            if !isOn { showInDock = true }
        }
        .onChange(of: showInDock) { _, isOn in
            DockPolicy.apply(showInDock: isOn)
        }
    }

    private var defaultFolders: [ScannedFolder] {
        ModelLibrary.folders(for: model.locations)
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let folder = CustomFolder(path: url.path, service: newFolderService)
        if !model.customFolders.contains(where: { $0.id == folder.id }) {
            model.customFolders.append(folder)
        }
        Task { await model.refresh() }
    }
}
