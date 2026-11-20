import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - 设计令牌（企业级克制风格）
// 对标 Ant Design / 华为云控制台：中性灰阶为主体，主色仅用于主操作，状态色仅承载语义。
enum Token {
    static let primary = Color(red: 0.088, green: 0.467, blue: 1.0)      // #1677FF
    static let primaryHover = Color(red: 0.255, green: 0.588, blue: 1.0) // #4096FF
    static let success = Color(red: 0.322, green: 0.769, blue: 0.102)    // #52C41A
    static let warning = Color(red: 0.980, green: 0.678, blue: 0.078)    // #FAAD14
    static let danger = Color(red: 1.0, green: 0.302, blue: 0.310)       // #FF4D4F

    static let textPrimary: Color = .primary
    static let textSecondary = Color.secondary
    static let textTertiary = Color(red: 0.45, green: 0.45, blue: 0.45)
    static let split = Color(nsColor: .separatorColor)
    static let layout = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)

    static let radiusCard: CGFloat = 8
    static let radiusControl: CGFloat = 6
    static let radiusTag: CGFloat = 2
}

// MARK: - 目录选择（AppKit 桥接）

struct DirectoryPicker {
    static func pick() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "选择文件夹"
        panel.message = "选择要整理的照片根目录（将递归扫描其子文件夹）"
        return panel.runModal() == .OK ? panel.url : nil
    }
}

// MARK: - App 入口

@main
struct BatchPhotoManagerApp: App {
    @StateObject private var store = PhotoManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 900, minHeight: 640)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

// MARK: - 主视图

struct ContentView: View {
    @EnvironmentObject var store: PhotoManager
    @State private var selectedTask: PhotoTask? = .unmatchedRaw
    @State private var confirmTask: PhotoTask?
    @State private var showUndoConfirm = false
    @State private var result: OperationResult?
    @State private var undoResult: UndoResult?
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            TopBar(selectedTask: $selectedTask, showUndoConfirm: $showUndoConfirm)
            Divider()
            OverviewBar()
            Divider()

            HStack(spacing: 0) {
                TaskSidebar(selectedTask: $selectedTask)
                Divider()
                DetailPanel(selectedTask: $selectedTask, confirmTask: $confirmTask)
            }
            .frame(maxHeight: .infinity)

            Divider()
            StatusBar(showUndoConfirm: $showUndoConfirm)
        }
        .background(Token.layout)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isDropTargeted ? Token.primary : Color.clear, lineWidth: 3)
                .padding(2)
                .allowsHitTesting(false)
        )
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .sheet(item: $result) { item in
            ResultSheet(result: item)
        }
        .sheet(item: $undoResult) { item in
            UndoResultSheet(result: item)
        }
        .alert(item: $confirmTask) { task in
            confirmAlert(for: task)
        }
        .alert("撤销最近一次操作", isPresented: $showUndoConfirm) {
            Button("取消", role: .cancel) {}
            Button("撤销", role: .destructive) { undoResult = store.undoLast() }
        } message: {
            Text("将把最近一次操作的文件恢复到原位置。若上次是删除操作，文件会从废纸篓搬回。已撤销过的操作不可重复撤销。")
        }
    }

    /// 拖入文件夹设为根目录。支持多个 provider，取第一个文件夹。
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url = url else { return }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                DispatchQueue.main.async {
                    store.lastMessage = "拖入的不是文件夹，请拖入一个文件夹"
                }
                return
            }
            // 解析符号链接，避免拿到别名路径
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL
            DispatchQueue.main.async {
                store.setRoot(resolved)
                selectedTask = .unmatchedRaw
            }
        }
        return true
    }

    private func confirmAlert(for task: PhotoTask) -> Alert {
        let count = store.preview(for: task).count
        let isDelete = task.isTrashTask
        let target = isDelete ? "系统废纸篓（可恢复）" : (store.targetURL(for: task)?.path ?? "各源文件夹内")
        let message = isDelete
            ? "将把 \(count) 个文件移到系统废纸篓，不是永久删除。\n可从废纸篓找回，也可在本软件一键撤销。\n\n请确认这些文件确实不再需要。"
            : "将\(task.actionText) \(count) 个文件。\n目标位置：\(target)\n\n操作会记录日志，可一键撤销。"
        return Alert(
            title: Text(isDelete ? "确认删除 \(count) 个文件" : "确认\(task.actionText)文件"),
            message: Text(message),
            primaryButton: isDelete
                ? .destructive(Text("移到废纸篓")) { result = store.run(task) }
                : .default(Text("确认\(task.actionText)")) { result = store.run(task) },
            secondaryButton: .cancel(Text("取消"))
        )
    }
}

// MARK: - 顶部栏

struct TopBar: View {
    @EnvironmentObject var store: PhotoManager
    @Binding var selectedTask: PhotoTask?
    @Binding var showUndoConfirm: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("批量管理照片软件")
                    .font(.system(size: 16, weight: .semibold))
                Text("RAW / JPG 批量整理 · 可拖入文件夹 · 可撤销")
                    .font(.system(size: 11))
                    .foregroundColor(Token.textTertiary)
            }

            Spacer()

            if let root = store.rootURL {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .foregroundColor(Token.textTertiary)
                    Text(root.path)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Token.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(root.path)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Token.card)
                .cornerRadius(Token.radiusControl)

                Button {
                    store.rescan()
                } label: {
                    Label("重新扫描", systemImage: "arrow.clockwise")
                }
                .disabled(store.isScanning)
                .help("文件夹内容变化后重新统计")

                // 撤销入口：撤销最近一次整理/删除操作
                Button {
                    showUndoConfirm = true
                } label: {
                    Label("撤销", systemImage: "arrow.uturn.backward")
                }
                .disabled(!store.canUndo)
                .keyboardShortcut("z", modifiers: .command)
                .help("撤销最近一次操作（⌘Z）")
            }

            Button {
                if let url = DirectoryPicker.pick() {
                    store.setRoot(url)
                    selectedTask = .unmatchedRaw
                }
            } label: {
                Label(store.rootURL == nil ? "选择文件夹" : "更换文件夹", systemImage: "folder.badge.plus")
            }
            .keyboardShortcut("o", modifiers: .command)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Token.card)
    }
}

// MARK: - 概览条

struct OverviewBar: View {
    @EnvironmentObject var store: PhotoManager

    var body: some View {
        HStack(spacing: 12) {
            MetricCard(title: "扫描文件夹", value: "\(store.stats.dirCount)", unit: "个", icon: "folder", tone: .neutral)
            MetricCard(title: "RAW 文件", value: "\(store.stats.rawCount)", unit: "个", icon: "camera.aperture", tone: .neutral)
            MetricCard(title: "JPG 文件", value: "\(store.stats.jpgCount)", unit: "个", icon: "photo", tone: .neutral)
            MetricCard(
                title: "无匹配 JPG 的 RAW",
                value: "\(store.stats.unmatchedRawCount)",
                unit: "个",
                icon: "exclamationmark.triangle",
                tone: store.stats.unmatchedRawCount > 0 ? .warning : .neutral
            )
            MetricCard(
                title: "有匹配 JPG 的 RAW",
                value: "\(store.stats.matchedRawCount)",
                unit: "个",
                icon: "checkmark.circle",
                tone: store.stats.matchedRawCount > 0 ? .success : .neutral
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Token.layout)
        .opacity(store.rootURL == nil ? 0.45 : 1.0)
    }
}

enum MetricTone { case neutral, success, warning }

struct MetricCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let tone: MetricTone

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(toneColor)
                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(Token.textSecondary)
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(Token.textPrimary)
                    .monospacedDigit()
                Text(unit)
                    .font(.system(size: 11))
                    .foregroundColor(Token.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Token.card)
        .cornerRadius(Token.radiusCard)
        .overlay(
            RoundedRectangle(cornerRadius: Token.radiusCard)
                .stroke(Token.split, lineWidth: 1)
        )
    }

    private var toneColor: Color {
        switch tone {
        case .neutral: return Token.textTertiary
        case .success: return Token.success
        case .warning: return Token.warning
        }
    }
}

// MARK: - 左侧任务列表

struct TaskSidebar: View {
    @EnvironmentObject var store: PhotoManager
    @Binding var selectedTask: PhotoTask?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(TaskGroup.allCases) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.title.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Token.textTertiary)
                            .padding(.horizontal, 10)

                        ForEach(PhotoTask.allCases.filter { $0.group == group }) { task in
                            TaskRow(
                                task: task,
                                count: store.preview(for: task).count,
                                selected: selectedTask == task
                            )
                            .onTapGesture { selectedTask = task }
                        }
                    }
                }

                Divider()
                    .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 6) {
                    Text("操作记录（⌘Z 撤销最近一次）")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Token.textTertiary)
                        .padding(.horizontal, 10)

                    let transactions = store.transactionSummaries(limit: 8)
                    if transactions.isEmpty {
                        Text("暂无操作记录")
                            .font(.system(size: 12))
                            .foregroundColor(Token.textTertiary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(transactions) { tx in
                            TransactionRow(summary: tx)
                        }
                    }
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 8)
        }
        .frame(width: 244)
        .background(Token.card)
    }
}

struct TaskRow: View {
    let task: PhotoTask
    let count: Int
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: task.icon)
                .font(.system(size: 13))
                .foregroundColor(selected ? Token.primary : Token.textTertiary)
                .frame(width: 18)

            Text(task.title)
                .font(.system(size: 13))
                .foregroundColor(selected ? Token.primary : Token.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)

            Text("\(count)")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundColor(count > 0 ? Token.textSecondary : Token.textTertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(count > 0 ? Token.layout : Color.clear)
                .cornerRadius(Token.radiusTag)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(selected ? Token.primary.opacity(0.09) : Color.clear)
        .cornerRadius(Token.radiusControl)
        .overlay(
            RoundedRectangle(cornerRadius: Token.radiusControl)
                .stroke(selected ? Token.primary.opacity(0.25) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}

struct TransactionRow: View {
    let summary: TransactionSummary

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 10))
                .foregroundColor(Token.textTertiary)
            VStack(alignment: .leading, spacing: 1) {
                Text(summary.description)
                    .font(.system(size: 11))
                    .foregroundColor(summary.deleteCount > 0 ? Token.danger : Token.textSecondary)
                if let time = summary.time {
                    Text(timeFormatter.string(from: time))
                        .font(.system(size: 10))
                        .foregroundColor(Token.textTertiary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f
    }
}

// MARK: - 右侧详情

struct DetailPanel: View {
    @EnvironmentObject var store: PhotoManager
    @Binding var selectedTask: PhotoTask?
    @Binding var confirmTask: PhotoTask?

    var body: some View {
        Group {
            if let task = selectedTask {
                DetailContent(task: task, confirmTask: $confirmTask)
            } else {
                EmptyState()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Token.layout)
    }
}

struct DetailContent: View {
    @EnvironmentObject var store: PhotoManager
    let task: PhotoTask
    @Binding var confirmTask: PhotoTask?

    private var items: [PreviewItem] { store.preview(for: task) }
    private var sourceDirCount: Int { Set(items.map { $0.sourceDir.path }).count }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 标题区
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: task.icon)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(Token.primary)
                            Text(task.title)
                                .font(.system(size: 18, weight: .semibold))
                        }
                        Text(task.detail)
                            .font(.system(size: 13))
                            .foregroundColor(Token.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // 标签区
                    HStack(spacing: 8) {
                        InfoTag(icon: "folder", text: "范围：\(task.scopeText)")
                        InfoTag(icon: task.isTrashTask ? "trash" : "arrow.right",
                                text: "动作：\(task.actionText)", danger: task.isTrashTask)
                        InfoTag(icon: "square.stack", text: "目标：\(task.targetDirName)")
                    }

                    // 影响概览
                    HStack(spacing: 20) {
                        ImpactStat(label: "预计处理文件", value: "\(items.count)", unit: "个", highlight: true)
                        ImpactStat(label: "涉及源文件夹", value: "\(sourceDirCount)", unit: "个", highlight: false)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Token.card)
                    .cornerRadius(Token.radiusCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: Token.radiusCard)
                            .stroke(Token.split, lineWidth: 1)
                    )

                    // 目标位置
                    VStack(alignment: .leading, spacing: 6) {
                        Text("目标位置")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Token.textSecondary)
                        HStack(spacing: 6) {
                            Image(systemName: "folder")
                                .font(.system(size: 11))
                                .foregroundColor(Token.textTertiary)
                            Text(targetPathText)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(Token.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    Divider()

                    // 预览列表
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("文件预览")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            if items.count > 10 {
                                Text("显示前 10 / 共 \(items.count) 个")
                                    .font(.system(size: 11))
                                    .foregroundColor(Token.textTertiary)
                            }
                        }

                        if items.isEmpty {
                            EmptyPreview()
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(items.prefix(10))) { item in
                                    PreviewRow(item: item)
                                    if item.id != items.prefix(10).last?.id {
                                        Divider()
                                    }
                                }
                            }
                            .background(Token.card)
                            .cornerRadius(Token.radiusCard)
                            .overlay(
                                RoundedRectangle(cornerRadius: Token.radiusCard)
                                    .stroke(Token.split, lineWidth: 1)
                            )
                        }
                    }
                }
                .padding(20)
            }

            Divider()

            // 底部操作区
            HStack(spacing: 12) {
                Text(task.isTrashTask
                     ? "文件将移到废纸篓（可恢复），并写入日志支持撤销。"
                     : "所有操作都会记录日志，可在顶部或状态栏一键撤销。")
                    .font(.system(size: 11))
                    .foregroundColor(task.isTrashTask ? Token.danger : Token.textTertiary)
                Spacer()
                Button {
                    confirmTask = task
                } label: {
                    Label("\(task.actionText) \(items.count) 个文件",
                          systemImage: task.isTrashTask ? "trash" : "play.fill")
                        .frame(minWidth: 150)
                }
                .buttonStyle(.borderedProminent)
                .tint(task.isTrashTask ? Token.danger : Token.primary)
                .controlSize(.large)
                .disabled(items.isEmpty || store.isScanning)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Token.card)
        }
    }

    private var targetPathText: String {
        if let url = store.targetURL(for: task) {
            return url.path
        }
        return "各源文件夹下的「\(task.targetDirName)」子目录"
    }
}

struct InfoTag: View {
    let icon: String
    let text: String
    var danger = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 11))
        }
        .foregroundColor(danger ? Token.danger : Token.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Token.card)
        .cornerRadius(Token.radiusTag)
        .overlay(
            RoundedRectangle(cornerRadius: Token.radiusTag)
                .stroke(Token.split, lineWidth: 1)
        )
    }
}

struct ImpactStat: View {
    let label: String
    let value: String
    let unit: String
    let highlight: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(Token.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(highlight ? Token.primary : Token.textPrimary)
                    .monospacedDigit()
                Text(unit)
                    .font(.system(size: 11))
                    .foregroundColor(Token.textTertiary)
            }
        }
    }
}

struct PreviewRow: View {
    let item: PreviewItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.isCopy ? "doc.on.doc" : "arrow.right")
                .font(.system(size: 11))
                .foregroundColor(Token.textTertiary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.sourceName)
                    .font(.system(size: 12))
                    .foregroundColor(Token.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("来自：\(item.sourceDir.lastPathComponent)")
                    .font(.system(size: 10))
                    .foregroundColor(Token.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            Text("→ \(item.targetRelativePath)")
                .font(.system(size: 10))
                .foregroundColor(Token.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct EmptyPreview: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 24))
                .foregroundColor(Token.textTertiary)
            Text("没有符合条件的文件")
                .font(.system(size: 13))
                .foregroundColor(Token.textSecondary)
            Text("当前任务下无需处理，可切换其他任务")
                .font(.system(size: 11))
                .foregroundColor(Token.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(Token.card)
        .cornerRadius(Token.radiusCard)
        .overlay(
            RoundedRectangle(cornerRadius: Token.radiusCard)
                .stroke(Token.split, lineWidth: 1)
        )
    }
}

struct EmptyState: View {
    @EnvironmentObject var store: PhotoManager

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 44))
                .foregroundColor(Token.textTertiary)
            Text("请先选择照片文件夹")
                .font(.system(size: 16, weight: .medium))
            Text("把文件夹直接拖进窗口，或点击下面按钮选择。选择后将自动扫描 RAW 与 JPG 文件，按同名规则统计可整理的项目。")
                .font(.system(size: 12))
                .foregroundColor(Token.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            Button {
                if let url = DirectoryPicker.pick() { store.setRoot(url) }
            } label: {
                Label("选择文件夹", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(Token.primary)
            .controlSize(.large)

            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                Text("匹配规则：主文件名相同（不区分大小写）即视为一对")
                    .font(.system(size: 11))
            }
            .foregroundColor(Token.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 状态栏

struct StatusBar: View {
    @EnvironmentObject var store: PhotoManager
    @Binding var showUndoConfirm: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(store.lastMessage.isEmpty ? Token.textTertiary : Token.success)
                .frame(width: 6, height: 6)
            Text(store.lastMessage.isEmpty ? "就绪 · 可把文件夹直接拖进窗口" : store.lastMessage)
                .font(.system(size: 11))
                .foregroundColor(Token.textSecondary)
                .lineLimit(1)
            Spacer()
            if store.canUndo {
                Button {
                    showUndoConfirm = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward")
                        Text("撤销最近一次（可撤销 \(store.transactionSummaries(limit: 100).count) 次）")
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundColor(Token.primary)
                .help("撤销最近一次操作（⌘Z）")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Token.card)
    }
}

// MARK: - 结果弹窗

struct ResultSheet: View {
    let result: OperationResult
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: result.failed == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(result.failed == 0 ? Token.success : Token.warning)
                Text(result.failed == 0 ? "整理完成" : "整理完成（部分失败）")
                    .font(.system(size: 16, weight: .semibold))
            }
            Text("文件已移到系统废纸篓，可从废纸篓找回，也可 ⌘Z 撤销。")
                .font(.system(size: 11))
                .foregroundColor(Token.textTertiary)
                .opacity(result.isTrash && result.succeeded > 0 ? 1 : 0)

            if result.noFilesHint {
                Text("没有符合条件的文件需要处理。")
                    .font(.system(size: 13))
                    .foregroundColor(Token.textSecondary)
            } else {
                HStack(spacing: 24) {
                    ResultStat(label: "成功", value: "\(result.succeeded)", color: Token.success)
                    ResultStat(label: "失败", value: "\(result.failed)", color: result.failed > 0 ? Token.danger : Token.textTertiary)
                }
                .padding(16)
                .background(Token.layout)
                .cornerRadius(Token.radiusCard)

                if let target = result.targetURL {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("目标位置").font(.system(size: 12)).foregroundColor(Token.textSecondary)
                        HStack(spacing: 6) {
                            Image(systemName: "folder").font(.system(size: 11)).foregroundColor(Token.textTertiary)
                            Text(target.path).font(.system(size: 11, design: .monospaced))
                                .lineLimit(2).truncationMode(.middle)
                        }
                    }
                }

                if !result.failureDetails.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("失败详情").font(.system(size: 12, weight: .medium)).foregroundColor(Token.danger)
                        ForEach(result.failureDetails.prefix(5), id: \.self) { detail in
                            Text(detail).font(.system(size: 11)).foregroundColor(Token.textSecondary)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}

struct ResultStat: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 12)).foregroundColor(Token.textSecondary)
            Text(value).font(.system(size: 24, weight: .semibold)).foregroundColor(color).monospacedDigit()
        }
    }
}

struct UndoResultSheet: View {
    let result: UndoResult
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: result.restored == 0 && result.failed == 0 ? "tray" : "arrow.uturn.backward.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(result.failed == 0 ? Token.success : Token.warning)
                Text(result.restored == 0 && result.failed == 0 ? "没有可撤销的操作" : "撤销完成")
                    .font(.system(size: 16, weight: .semibold))
            }

            if result.restored > 0 || result.failed > 0 {
                HStack(spacing: 20) {
                    ResultStat(label: "恢复", value: "\(result.restored)", color: Token.success)
                    if result.trashedRestored > 0 {
                        ResultStat(label: "从废纸篓搬回", value: "\(result.trashedRestored)", color: Token.primary)
                    }
                    ResultStat(label: "自动改名", value: "\(result.renamed)", color: Token.textPrimary)
                    ResultStat(label: "失败", value: "\(result.failed)", color: result.failed > 0 ? Token.danger : Token.textTertiary)
                }
                .padding(16)
                .background(Token.layout)
                .cornerRadius(Token.radiusCard)

                Text(result.trashedRestored > 0
                     ? "删除的文件已从废纸篓搬回原位置。若原位置已有同名文件，会自动添加 _1、_2 后缀，不会覆盖。"
                     : "文件已放回原位置。若原位置已有同名文件，会自动添加 _1、_2 后缀，不会覆盖。")
                    .font(.system(size: 11))
                    .foregroundColor(Token.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}
