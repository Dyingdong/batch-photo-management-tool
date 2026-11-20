import Foundation
import AppKit

// MARK: - 文件类型

enum FileKind: String {
    case raw
    case jpg
}

extension FileKind {
    /// 覆盖主流相机 RAW 格式（整合 photo_workflow.py 的 CR3 与 photo_workflow1.py 的全格式）
    static let rawSuffixes: Set<String> = [
        "cr2", "cr3",                 // Canon
        "nef", "nrw",                 // Nikon
        "arw", "srf", "sr2",          // Sony
        "raf",                        // Fujifilm
        "orf",                        // Olympus / OM System
        "rw2",                        // Panasonic
        "pef",                        // Pentax
        "srw",                        // Samsung
        "dng", "raw",                 // 通用
    ]
    static let jpgSuffixes: Set<String> = ["jpg", "jpeg"]

    static func classify(_ name: String) -> FileKind? {
        let ext = (name as NSString).pathExtension.lowercased()
        if rawSuffixes.contains(ext) { return .raw }
        if jpgSuffixes.contains(ext) { return .jpg }
        return nil
    }
}

/// 工具自身生成的目录：遍历时必须跳过，避免重复整理自己的输出。
enum GeneratedDir {
    static let names: Set<String> = [
        // photo_workflow1.py
        "无同名JPG的RAW", "全部RAW", "当前目录同名JPG的RAW",
        "所有目录同名JPG的RAW", "当前目录JPG", "所有目录JPG",
        // photo_workflow.py
        "无匹配JPG的CR3文件", "全部CR3文件", "有匹配JPG的CR3文件",
        "所有匹配JPG的CR3文件", "当前文件夹JPG照片", "所有文件夹JPG照片",
        // 摄影小工具.py / move_unused_raw.py
        "unused_raw_files", "all_raw_files", "matched_raw_files",
    ]
    static let logFileName = "操作日志.jsonl"
}

// MARK: - 任务定义

enum TaskGroup: String, CaseIterable, Identifiable {
    case raw
    case jpg
    case cleanup

    var id: String { rawValue }
    var title: String {
        switch self {
        case .raw: return "RAW 整理"
        case .jpg: return "JPG 整理"
        case .cleanup: return "清理（移到废纸篓）"
        }
    }
}

/// 整理操作：只描述「做什么」，处理范围（是否含子文件夹）由全局开关决定，不再枚举组合。
enum PhotoTask: String, CaseIterable, Identifiable {
    case matchedRaw
    case allRaw
    case unmatchedRaw
    case jpg
    case deleteUnmatchedRaw
    case deleteOrphanJpg

    var id: String { rawValue }

    var group: TaskGroup {
        switch self {
        case .unmatchedRaw, .allRaw, .matchedRaw: return .raw
        case .jpg: return .jpg
        case .deleteUnmatchedRaw, .deleteOrphanJpg: return .cleanup
        }
    }

    var title: String {
        switch self {
        case .unmatchedRaw:         return "移出无同名 JPG 的 RAW"
        case .allRaw:               return "汇总全部 RAW"
        case .matchedRaw:           return "移出有同名 JPG 的 RAW"
        case .jpg:                  return "汇总全部JPG"
        case .deleteUnmatchedRaw:   return "删除无同名 JPG 的 RAW"
        case .deleteOrphanJpg:      return "删除无同名 RAW 的 JPG"
        }
    }

    var icon: String {
        switch self {
        case .unmatchedRaw:         return "arrow.right.circle"
        case .allRaw:               return "square.stack.3d.up"
        case .matchedRaw:           return "arrow.right.circle.fill"
        case .jpg:                  return "square.on.square"
        case .deleteUnmatchedRaw:   return "trash"
        case .deleteOrphanJpg:      return "trash.circle"
        }
    }

    func detail(includeSubfolders: Bool) -> String {
        let scope = includeSubfolders ? "递归处理当前文件夹及其所有子文件夹" : "只处理当前文件夹（不含子文件夹）"
        switch self {
        case .unmatchedRaw:
            return "\(scope)：把没有同名 JPG 的 RAW 移到各自所在文件夹下的「无同名JPG的RAW」子目录。"
        case .allRaw:
            return "\(scope)：把找到的 RAW 复制一份到根目录的「全部RAW」，原文件保留不动。"
        case .matchedRaw:
            return "\(scope)：把有同名 JPG 的 RAW 移到目标目录。"
        case .jpg:
            return "\(scope)：把 JPG 移到目标目录。"
        case .deleteUnmatchedRaw:
            return "\(scope)：把没有同名 JPG 的 RAW 移到系统废纸篓（不是永久删除，可从废纸篓找回，也可在本软件撤销）。"
        case .deleteOrphanJpg:
            return "\(scope)：把没有同名 RAW 的 JPG 移到系统废纸篓（不是永久删除，可从废纸篓找回，也可在本软件撤销）。"
        }
    }

    /// 范围说明文字，跟随全局开关变化
    func scopeText(includeSubfolders: Bool) -> String {
        includeSubfolders ? "包括子文件夹（递归）" : "仅当前文件夹（不含子文件夹）"
    }

    var actionText: String {
        switch self {
        case .allRaw: return "复制"
        case .deleteUnmatchedRaw, .deleteOrphanJpg: return "删除"
        default: return "移动"
        }
    }

    /// 是否为「移到废纸篓」的删除类任务（危险操作，需要红色确认）
    var isTrashTask: Bool {
        switch self {
        case .deleteUnmatchedRaw, .deleteOrphanJpg: return true
        default: return false
        }
    }

    /// 目标目录名：部分任务随范围开关切换，保持与旧版本目录名兼容
    func targetDirName(includeSubfolders: Bool) -> String {
        switch self {
        case .unmatchedRaw: return "无同名JPG的RAW"
        case .allRaw:       return "全部RAW"
        case .matchedRaw:   return includeSubfolders ? "所有目录同名JPG的RAW" : "当前目录同名JPG的RAW"
        case .jpg:          return includeSubfolders ? "所有目录JPG" : "当前目录JPG"
        case .deleteUnmatchedRaw, .deleteOrphanJpg: return "系统废纸篓"
        }
    }

    /// 目标目录是否在根目录下统一存放（false 表示每个源目录各放一个）
    var usesRootTarget: Bool {
        switch self {
        case .unmatchedRaw, .deleteUnmatchedRaw, .deleteOrphanJpg: return false
        default: return true
        }
    }
}

// MARK: - 数据模型

struct FileSnapshot: Hashable {
    let url: URL
    let name: String
    let stem: String
    let kind: FileKind
}

struct DirSnapshot {
    let url: URL
    let relativePath: String
    let rawFiles: [FileSnapshot]
    let jpgFiles: [FileSnapshot]
    let matchedRaw: [FileSnapshot]
    let unmatchedRaw: [FileSnapshot]
    let orphanJpg: [FileSnapshot]
}

struct LibraryStats {
    var dirCount = 0
    var rawCount = 0
    var jpgCount = 0
    var matchedRawCount = 0
    var unmatchedRawCount = 0
    var orphanJpgCount = 0
}

struct PreviewItem: Identifiable {
    let source: URL
    let target: URL
    let sourceDir: URL
    let isCopy: Bool
    var id: String { source.path }

    var sourceName: String { source.lastPathComponent }
    var targetRelativePath: String { target.lastPathComponent }
}

struct LogRecord: Codable, Identifiable {
    let tx: String
    let type: String          // mkdir / move / copy
    let src: String
    let dst: String
    var time: Date?

    var id: String { tx + "|" + type + "|" + src + "|" + dst }

    enum CodingKeys: String, CodingKey { case tx, type, src, dst, time }

    init(tx: String, type: String, src: String = "", dst: String = "", time: Date? = Date()) {
        self.tx = tx
        self.type = type
        self.src = src
        self.dst = dst
        self.time = time
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tx = try c.decode(String.self, forKey: .tx)
        type = try c.decode(String.self, forKey: .type)
        src = try c.decodeIfPresent(String.self, forKey: .src) ?? ""
        dst = try c.decodeIfPresent(String.self, forKey: .dst) ?? ""
        time = try c.decodeIfPresent(Date.self, forKey: .time)
    }
}

struct OperationResult: Identifiable {
    let id = UUID()
    var succeeded = 0
    var failed = 0
    var failureDetails: [String] = []
    var targetURL: URL?
    var noFilesHint = false
    var isTrash = false
}

struct UndoResult: Identifiable {
    let id = UUID()
    var restored = 0
    var renamed = 0
    var failed = 0
    var trashedRestored = 0   // 其中从废纸篓搬回的数量
    var tx: String?
}

struct TransactionSummary: Identifiable {
    let tx: String
    let time: Date?
    let moveCount: Int
    let copyCount: Int
    let deleteCount: Int
    var id: String { tx }

    var description: String {
        var parts: [String] = []
        if moveCount > 0 { parts.append("移动 \(moveCount)") }
        if copyCount > 0 { parts.append("复制 \(copyCount)") }
        if deleteCount > 0 { parts.append("删除 \(deleteCount)") }
        return parts.isEmpty ? "操作" : parts.joined(separator: " · ")
    }
}

// MARK: - 核心管理器

final class PhotoManager: ObservableObject {
    @Published var rootURL: URL?
    /// 处理范围：默认包括子文件夹；关闭后所有任务只处理根目录（每个操作独立决定不重复枚举）。
    /// 切换时立即按新范围重算统计，界面数字随勾选框实时刷新。
    @Published var includeSubfolders = true {
        didSet { recalcStats() }
    }
    @Published var stats = LibraryStats()
    @Published var isScanning = false
    @Published var snapshots: [DirSnapshot] = []
    @Published var logs: [LogRecord] = []
    @Published var lastMessage = ""

    private var currentTx: String?
    private var securityScoped = false

    deinit {
        if securityScoped { rootURL?.stopAccessingSecurityScopedResource() }
    }

    // MARK: 目录选择

    func setRoot(_ url: URL) {
        if securityScoped { rootURL?.stopAccessingSecurityScopedResource() }
        securityScoped = url.startAccessingSecurityScopedResource()
        rootURL = url
        rescan()
    }

    // MARK: 扫描

    func rescan() {
        guard let root = rootURL else {
            snapshots = []
            stats = LibraryStats()
            return
        }
        isScanning = true
        defer { isScanning = false }

        let dirs = collectDirs(root: root)
        var result: [DirSnapshot] = []

        for dir in dirs {
            let files = filesIn(dir)
            var raws: [FileSnapshot] = []
            var jpgs: [FileSnapshot] = []
            for file in files {
                switch file.kind {
                case .raw: raws.append(file)
                case .jpg: jpgs.append(file)
                }
            }
            let jpgStems = Set(jpgs.map { $0.stem })
            let rawStems = Set(raws.map { $0.stem })
            let matched = raws.filter { jpgStems.contains($0.stem) }
            let unmatched = raws.filter { !jpgStems.contains($0.stem) }
            let orphanJpg = jpgs.filter { !rawStems.contains($0.stem) }

            let relative: String
            if dir.path == root.path {
                relative = "（根目录）"
            } else {
                let prefix = root.path + "/"
                relative = dir.path.hasPrefix(prefix) ? String(dir.path.dropFirst(prefix.count)) : dir.lastPathComponent
            }

            result.append(DirSnapshot(
                url: dir,
                relativePath: relative,
                rawFiles: raws,
                jpgFiles: jpgs,
                matchedRaw: matched,
                unmatchedRaw: unmatched,
                orphanJpg: orphanJpg
            ))
        }

        snapshots = result
        recalcStats()
        logs = loadLogs()
    }

    /// 按当前范围（含/不含子文件夹）重新聚合概览统计。
    /// 勾选框切换、扫描完成后都会调用，确保统计数字与处理范围一致。
    private func recalcStats() {
        guard let root = rootURL else {
            stats = LibraryStats()
            return
        }
        let dirs = scopedDirs(root: root)
        var s = LibraryStats()
        s.dirCount = dirs.count
        for dir in dirs {
            s.rawCount += dir.rawFiles.count
            s.jpgCount += dir.jpgFiles.count
            s.matchedRawCount += dir.matchedRaw.count
            s.unmatchedRawCount += dir.unmatchedRaw.count
            s.orphanJpgCount += dir.orphanJpg.count
        }
        stats = s
    }

    private func collectDirs(root: URL) -> [URL] {
        var dirs: [URL] = []
        let fm = FileManager.default

        func walk(_ dir: URL) {
            dirs.append(dir)
            guard let entries = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { return }

            for entry in entries {
                let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                guard isDir else { continue }
                let name = entry.lastPathComponent
                guard !GeneratedDir.names.contains(name) else { continue }
                guard !name.hasPrefix(".") else { continue }
                walk(entry)
            }
        }

        walk(root)
        return dirs
    }

    private func filesIn(_ dir: URL) -> [FileSnapshot] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [FileSnapshot] = []
        for entry in entries {
            let isFile = (try? entry.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            guard isFile else { continue }
            let name = entry.lastPathComponent
            guard let kind = FileKind.classify(name) else { continue }
            let stem = (name as NSString).deletingPathExtension
                .trimmingCharacters(in: .whitespaces).lowercased()
            files.append(FileSnapshot(url: entry, name: name, stem: stem, kind: kind))
        }
        return files
    }

    // MARK: 预览

    /// 按当前范围开关返回待处理的目录：关闭时只保留根目录。
    private func scopedDirs(root: URL) -> [DirSnapshot] {
        includeSubfolders ? snapshots : snapshots.filter { $0.url.path == root.path }
    }

    func preview(for task: PhotoTask) -> [PreviewItem] {
        guard let root = rootURL else { return [] }
        let dirs = scopedDirs(root: root)
        let targetName = task.targetDirName(includeSubfolders: includeSubfolders)
        var items: [PreviewItem] = []

        switch task {
        case .unmatchedRaw:
            for dir in dirs {
                let targetDir = dir.url.appendingPathComponent(targetName, isDirectory: true)
                for file in dir.unmatchedRaw {
                    items.append(PreviewItem(
                        source: file.url,
                        target: targetDir.appendingPathComponent(file.name),
                        sourceDir: dir.url,
                        isCopy: false
                    ))
                }
            }

        case .allRaw, .matchedRaw, .jpg:
            let targetDir = root.appendingPathComponent(targetName, isDirectory: true)
            for dir in dirs {
                let files: [FileSnapshot]
                switch task {
                case .allRaw:     files = dir.rawFiles
                case .matchedRaw: files = dir.matchedRaw
                default:          files = dir.jpgFiles
                }
                for file in files {
                    items.append(PreviewItem(
                        source: file.url,
                        target: targetDir.appendingPathComponent(file.name),
                        sourceDir: dir.url,
                        isCopy: task == .allRaw
                    ))
                }
            }

        case .deleteUnmatchedRaw, .deleteOrphanJpg:
            for dir in dirs {
                let files = task == .deleteUnmatchedRaw ? dir.unmatchedRaw : dir.orphanJpg
                for file in files {
                    // target 用源文件占位；删除任务不使用 target 做移动，仅用于预览展示
                    items.append(PreviewItem(
                        source: file.url,
                        target: file.url,
                        sourceDir: dir.url,
                        isCopy: false
                    ))
                }
            }
        }

        return items
    }

    func targetURL(for task: PhotoTask) -> URL? {
        guard let root = rootURL else { return nil }
        if task.usesRootTarget {
            return root.appendingPathComponent(
                task.targetDirName(includeSubfolders: includeSubfolders),
                isDirectory: true
            )
        }
        return nil
    }

    // MARK: 执行

    func run(_ task: PhotoTask) -> OperationResult {
        guard rootURL != nil else {
            var r = OperationResult()
            r.failureDetails.append("尚未选择文件夹")
            r.failed = 1
            return r
        }

        let items = preview(for: task)
        var result = OperationResult()
        result.isTrash = task.isTrashTask
        guard !items.isEmpty else {
            result.noFilesHint = true
            result.targetURL = targetURL(for: task)
            lastMessage = "没有文件需要处理"
            return result
        }

        beginTx()
        var ensuredDirs: Set<String> = []

        for item in items {
            if task.isTrashTask {
                safeTrash(item.source, result: &result)
                continue
            }
            let dir = item.target.deletingLastPathComponent()
            if !ensuredDirs.contains(dir.path) {
                safeMkdir(dir)
                ensuredDirs.insert(dir.path)
            }
            if item.isCopy {
                safeCopy(item.source, item.target, result: &result)
            } else {
                safeMove(item.source, item.target, result: &result)
            }
        }
        currentTx = nil

        result.targetURL = targetURL(for: task)
        let summary = result.failed == 0
            ? "完成：\(task.actionText) \(result.succeeded) 个文件到「\(task.targetDirName(includeSubfolders: includeSubfolders))」（\(task.scopeText(includeSubfolders: includeSubfolders))）"
            : "完成：成功 \(result.succeeded) 个，失败 \(result.failed) 个"
        lastMessage = summary
        rescan()
        return result
    }

    private func beginTx() {
        currentTx = UUID().uuidString
    }

    private func safeMkdir(_ dir: URL) {
        guard !FileManager.default.fileExists(atPath: dir.path) else { return }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            log("mkdir", dst: dir.path)
        } catch {
            // 目录创建失败会在后续文件操作中体现
        }
    }

    private func safeMove(_ src: URL, _ dst: URL, result: inout OperationResult) {
        let finalDst = uniquePath(dst)
        do {
            try FileManager.default.moveItem(at: src, to: finalDst)
            log("move", src: src.path, dst: finalDst.path)
            result.succeeded += 1
        } catch {
            result.failed += 1
            result.failureDetails.append("\(src.lastPathComponent)：\(error.localizedDescription)")
        }
    }

    private func safeCopy(_ src: URL, _ dst: URL, result: inout OperationResult) {
        let finalDst = uniquePath(dst)
        do {
            try FileManager.default.copyItem(at: src, to: finalDst)
            log("copy", src: src.path, dst: finalDst.path)
            result.succeeded += 1
        } catch {
            result.failed += 1
            result.failureDetails.append("\(src.lastPathComponent)：\(error.localizedDescription)")
        }
    }

    /// 移到系统废纸篓（不是永久删除）。记录 trash 后的实际路径，撤销时据此搬回原位置。
    private func safeTrash(_ src: URL, result: inout OperationResult) {
        var trashedURL: NSURL?
        do {
            try FileManager.default.trashItem(at: src, resultingItemURL: &trashedURL)
            let trashPath = trashedURL?.path ?? ""
            log("delete", src: src.path, dst: trashPath)
            result.succeeded += 1
        } catch {
            result.failed += 1
            result.failureDetails.append("\(src.lastPathComponent)：\(error.localizedDescription)")
        }
    }

    private func uniquePath(_ path: URL) -> URL {
        guard FileManager.default.fileExists(atPath: path.path) else { return path }
        let ext = path.pathExtension
        let base = (path.path as NSString).deletingPathExtension
        var index = 1
        while true {
            let name = ext.isEmpty ? "\(base)_\(index)" : "\(base)_\(index).\(ext)"
            let candidate = path.deletingLastPathComponent().appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }
            index += 1
        }
    }

    // MARK: 事务日志

    private func logFileURL() -> URL? {
        rootURL?.appendingPathComponent(GeneratedDir.logFileName)
    }

    private func log(_ type: String, src: String = "", dst: String = "") {
        guard let tx = currentTx, let url = logFileURL() else { return }
        let record = LogRecord(tx: tx, type: type, src: src, dst: dst)
        guard let data = try? JSONEncoder().encode(record) else { return }

        var all = Data()
        if let existing = try? Data(contentsOf: url) { all.append(existing) }
        if !all.isEmpty, all.last != 0x0A { all.append(Data([0x0A])) }
        all.append(data)
        all.append(Data([0x0A]))
        try? all.write(to: url)
    }

    func loadLogs() -> [LogRecord] {
        guard let url = logFileURL(),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return [] }

        return text.split(separator: "\n").compactMap { line in
            guard !line.isEmpty, let lineData = String(line).data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(LogRecord.self, from: lineData)
        }
    }

    private func saveLogs(_ records: [LogRecord]) {
        guard let url = logFileURL() else { return }
        let encoder = JSONEncoder()
        var all = Data()
        for record in records {
            guard let data = try? encoder.encode(record) else { continue }
            all.append(data)
            all.append(Data([0x0A]))
        }
        if all.isEmpty {
            try? FileManager.default.removeItem(at: url)
        } else {
            try? all.write(to: url)
        }
        logs = records
    }

    func transactionSummaries(limit: Int = 10) -> [TransactionSummary] {
        let records = logs
        var order: [String] = []
        var groups: [String: [LogRecord]] = [:]
        for record in records {
            if groups[record.tx] == nil { order.append(record.tx); groups[record.tx] = [] }
            groups[record.tx]?.append(record)
        }
        return order.reversed().prefix(limit).compactMap { tx in
            guard let group = groups[tx] else { return nil }
            return TransactionSummary(
                tx: tx,
                time: group.first?.time,
                moveCount: group.filter { $0.type == "move" }.count,
                copyCount: group.filter { $0.type == "copy" }.count,
                deleteCount: group.filter { $0.type == "delete" }.count
            )
        }
    }

    var canUndo: Bool { !logs.isEmpty }

    // MARK: 撤销

    func undoLast() -> UndoResult {
        let records = loadLogs()
        guard let lastTx = records.last?.tx else {
            lastMessage = "没有可撤销的操作"
            return UndoResult()
        }

        let group = records.filter { $0.tx == lastTx }
        var result = UndoResult()
        result.tx = lastTx
        let fm = FileManager.default

        for record in group.reversed() {
            switch record.type {
            case "move", "delete":
                // move：dst 是移动后的位置；delete：dst 是废纸篓里的实际路径。两者都是搬回 src。
                let dst = URL(fileURLWithPath: record.dst)
                let src = URL(fileURLWithPath: record.src)
                guard fm.fileExists(atPath: dst.path) else {
                    // 废纸篓已被清空 / 文件被手动移走时，尝试按原文件名找回
                    if record.type == "delete" { result.failed += 1 }
                    continue
                }
                let final = uniquePath(src)
                do {
                    try fm.createDirectory(
                        at: final.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try fm.moveItem(at: dst, to: final)
                    result.restored += 1
                    if final.path != src.path { result.renamed += 1 }
                    if record.type == "delete" { result.trashedRestored += 1 }
                } catch {
                    result.failed += 1
                }

            case "copy":
                let dst = URL(fileURLWithPath: record.dst)
                guard fm.fileExists(atPath: dst.path) else { continue }
                do {
                    try fm.removeItem(at: dst)
                    result.restored += 1
                } catch {
                    result.failed += 1
                }

            case "mkdir":
                let dir = URL(fileURLWithPath: record.dst)
                guard fm.fileExists(atPath: dir.path),
                      let contents = try? fm.contentsOfDirectory(atPath: dir.path),
                      contents.isEmpty else { continue }
                do {
                    try fm.removeItem(at: dir)
                    result.restored += 1
                } catch {
                    result.failed += 1
                }

            default:
                break
            }
        }

        saveLogs(records.filter { $0.tx != lastTx })
        var extra = ""
        if result.trashedRestored > 0 { extra += "（其中 \(result.trashedRestored) 个从废纸篓搬回）" }
        if result.renamed > 0 { extra += "（\(result.renamed) 个因同名已自动改名）" }
        lastMessage = "已撤销最近一次操作：恢复 \(result.restored) 项\(extra)"
        rescan()
        return result
    }
}
