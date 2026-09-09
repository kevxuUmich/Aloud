import AppKit
import Foundation
import Observation
import Prose
import Speech
import Vault

@Observable @MainActor
final class AppModel {
    let vault: Vault
    let player: Player
    let progress: ProgressStore
    let extraction = Extraction()
    private let rootStore = RootStore()
    private var watcher: FolderWatcher?
    private var openGeneration = 0

    var roots: [URL] = []
    var tree: [Folder] = []
    var path: [Route] = []
    var current: Document?
    var notice: String?

    init(provider: any VoiceProvider, progress: ProgressStore = .standard()) {
        self.player = Player(provider: provider)
        self.progress = progress
        let loaded = rootStore.load()
        self.roots = loaded
        self.vault = Vault(roots: loaded)
        player.onSentence = { [weak self] i in self?.record(index: i, finished: false) }
        player.onFinished = { [weak self] in
            guard let self, self.current != nil else { return }
            self.record(index: self.player.sentenceIndex, finished: true)
        }
    }

    func start() {
        Task { await refresh() }
        watch()
        Task { await restoreLast() }
    }

    func addRoot(_ url: URL) {
        roots = rootStore.add(url)
        Task {
            await vault.setRoots(roots); await refresh(); watch()
        }
    }

    func pickRootFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Read from this folder"
        if panel.runModal() == .OK, let url = panel.url { addRoot(url) }
    }

    func refresh() async {
        do {
            tree = try await vault.tree()
            let names = unreadableNames(in: tree)
            if !names.isEmpty {
                notice = "Could not read: " + names.joined(separator: ", ")
            }
        } catch {
            notice = "Could not read a vault folder: \(error.localizedDescription)"
        }
    }

    func open(_ doc: Document) {
        openGeneration += 1
        let generation = openGeneration
        Task {
            do {
                let kind: SourceKind = doc.type == .markdown ? .markdown : .plainText
                let script = try await extraction.script(for: doc.url, kind: kind, options: .default)
                guard generation == openGeneration else { return }
                let p = progress.progress(for: doc.url)
                current = doc
                player.load(script, at: p?.finished == true ? 0 : (p?.sentenceIndex ?? 0))
                if path.last != .reader(doc) { path.append(.reader(doc)) }
            } catch {
                guard generation == openGeneration else { return }
                notice = "Could not read \(doc.title): \(error.localizedDescription)"
            }
        }
    }

    func status(for doc: Document) -> String {
        if let p = progress.progress(for: doc.url) {
            if p.finished { return "Finished" }
            if p.sentenceIndex > 0, doc.id == current?.id {
                return Format.clock(player.remaining) + " left"
            }
            if p.sentenceIndex > 0 { return "In progress" }
        }
        let words = max(Estimate.words(in: doc.preview), doc.bytes / 6)
        return words == 0
            ? "" : "~" + Format.minutes(Estimate.duration(words: words, factor: player.rate.factor))
    }

    private func record(index: Int, finished: Bool) {
        guard let c = current else { return }
        progress.set(Progress(sentenceIndex: index, finished: finished, lastPlayed: .now), for: c.url)
    }

    func folder(at url: URL) -> Folder? {
        Self.find(url: url, in: tree)
    }

    private static func find(url: URL, in folders: [Folder]) -> Folder? {
        for f in folders {
            if f.url == url { return f }
            if let found = find(url: url, in: f.folders) { return found }
        }
        return nil
    }

    private func unreadableNames(in folders: [Folder]) -> [String] {
        folders.flatMap { f -> [String] in
            f.unreadable.map { $0.lastPathComponent } + unreadableNames(in: f.folders)
        }
    }

    private func watch() {
        watcher?.stop()
        guard !roots.isEmpty else { return }
        watcher = FolderWatcher(paths: roots) { [weak self] in
            Task { @MainActor in await self?.refresh() }
        }
    }

    private func restoreLast() async {
        guard let path = progress.lastPlayedPath() else { return }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path), let type = DocumentType(url: url), type != .pdf
        else { return }
        let kind: SourceKind = type == .markdown ? .markdown : .plainText
        if let script = try? await extraction.script(for: url, kind: kind, options: .default) {
            let doc = Document(
                url: url, title: Title.from(text: script.source, fallback: url.lastPathComponent),
                preview: "", modified: .now, bytes: 0, type: type)
            current = doc
            player.load(script, at: progress.progress(for: url)?.sentenceIndex ?? 0)
        }
    }
}
