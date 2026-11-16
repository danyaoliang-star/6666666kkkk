import SwiftUI

@MainActor
struct AccountView: View {
    @EnvironmentObject var store: AppStore
    @State private var logout = false
    var body: some View {
        List {
            Section {
                HStack(spacing: 15) { Image(systemName: "person.crop.circle.fill").font(.system(size: 45)).foregroundStyle(AppTheme.accent); VStack(alignment: .leading, spacing: 6) { Text(store.account?.name ?? "").font(.title3.bold()); Text(store.account?.username ?? "").font(.caption).foregroundStyle(.secondary) } }
                Text("服务：" + (store.api?.server.host ?? "")).font(.caption).foregroundStyle(.secondary)
            }
            Section("家庭") { NavigationLink { MembersView() } label: { Label("家庭成员与访问授权", systemImage: "person.2") }; NavigationLink { FamilyComparisonView() } label: { Label("家庭 Lp(a) 对照", systemImage: "point.3.connected.trianglepath.dotted") } }
            if let member = store.member {
                Section("当前档案 · " + member.name) {
                    if member.allows("read") {
                        NavigationLink { RecordsView(member: member) } label: { Label("健康记录", systemImage: "waveform.path.ecg") }
                        NavigationLink { ReportsView(member: member) } label: { Label("病历夹", systemImage: "folder") }
                        NavigationLink { MemoriesView(member: member) } label: { Label("健康记忆", systemImage: "brain.head.profile") }
                        NavigationLink { HealthDeviceView(member: member) } label: { Label("Apple 健康授权", systemImage: "heart") }
                    }
                    if member.allows("export") { NavigationLink { VisitExportView(member: member) } label: { Label("导出复诊资料", systemImage: "square.and.arrow.up") } }
                }
            }
            Section {
                Text("家和 · iPhone 原生版").font(.footnote)
                Text("健康记录用于日常管理，AI 回复与数据趋势请结合原件和医嘱核对。").font(.caption).foregroundStyle(.secondary)
                Button("退出登录", role: .destructive) { logout = true }.disabled(store.busy)
            }
        }.confirmationDialog("退出后需重新登录，当前手机不会保存账号密码。", isPresented: $logout, titleVisibility: .visible) { Button("退出登录", role: .destructive) { Task { await store.logout() } } }
    }
}

@MainActor
struct MembersView: View {
    @EnvironmentObject var store: AppStore
    @State private var editing: Member?
    @State private var editor = false
    var body: some View {
        List {
            ForEach(store.members) { member in
                Section {
                    HStack {
                        Button { store.select(member) } label: { HStack { Image(systemName: store.selectedID == member.id ? "checkmark.circle.fill" : "person.crop.circle"); VStack(alignment: .leading, spacing: 5) { Text(member.name).font(.headline); Text(member.relation + " · " + member.birthday).font(.caption).foregroundStyle(.secondary) } } }.buttonStyle(.plain)
                        Spacer()
                        if member.allows("manage") { Button("编辑") { editing = member; editor = true }.buttonStyle(.borderless).font(.caption) }
                    }
                    if !member.note.isEmpty { Text(member.note).font(.footnote).foregroundStyle(.secondary) }
                    if member.allows("manage") { NavigationLink("管理访问授权") { GrantsView(member: member) } }
                }
            }
            Button { editing = nil; editor = true } label: { Label("添加家庭成员", systemImage: "plus.circle") }
        }.navigationTitle("家庭成员").refreshable { await store.refreshMembers() }
            .sheet(isPresented: $editor) { NavigationStack { MemberEditor(existing: editing) } }
    }
}

@MainActor
struct MemberEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let existing: Member?
    @State private var name = ""
    @State private var relation = "本人"
    @State private var birthday = AppDates.date("2000-01-01")
    @State private var note = ""
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        Form {
            TextField("姓名", text: $name)
            TextField("与我的关系，如本人、父亲、母亲", text: $relation)
            DatePicker("出生日期", selection: $birthday, in: ...Date(), displayedComponents: .date)
            TextField("档案备注", text: $note, axis: .vertical).lineLimit(3...6)
            Text("只有由本账号管理、关系为“本人”的档案可接入当前 iPhone 的健康数据。").font(.caption).foregroundStyle(.secondary)
            InlineError(message: error)
            BusyButton(title: "保存档案", busy: busy) { Task { await save() } }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || relation.isEmpty)
        }.disabled(busy).navigationTitle(existing == nil ? "添加家人" : "编辑健康资料").navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(busy).toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) } }
            .onAppear { if let member = existing { name = member.name; relation = member.relation; birthday = AppDates.date(member.birthday); note = member.note } }
    }
    private func save() async {
        busy = true; error = nil; let context = store.generation; defer { busy = false }
        do {
            try await store.requireAPI().send("/members" + (existing.map { "/\($0.id)" } ?? ""), method: existing == nil ? "POST" : "PUT", body: ["name": name, "relation": relation, "birthday": AppDates.day(birthday), "note": note])
            guard store.isCurrent(context) else { return }; await store.refreshMembers(); dismiss()
        } catch { if store.isCurrent(context) { self.error = error.localizedDescription } }
    }
}

@MainActor
struct GrantsView: View {
    @EnvironmentObject var store: AppStore
    let member: Member
    @State private var grants: [AccessGrant] = []
    @State private var username = ""
    @State private var scope = "read"
    @State private var error: String?
    @State private var busy = false
    @State private var revoking: AccessGrant?
    let names = ["read": "查看健康资料", "write": "维护健康记录", "supervise": "查看计划监督", "export": "导出复诊资料"]
    var body: some View {
        Form {
            Section("给指定账号授权") {
                TextField("账号", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled()
                Picker("权限", selection: $scope) { ForEach(names.keys.sorted(), id: \.self) { Text(names[$0]!).tag($0) } }
                Button("添加授权") { Task { await add() } }.disabled(busy || username.isEmpty)
                Text("每项权限独立生效。Apple 健康摘要仅本人导入账号可见，不随上述权限共享。").font(.caption).foregroundStyle(.secondary)
            }
            InlineError(message: error)
            Section("\(member.name)的现有授权") { ForEach(grants) { row in HStack { VStack(alignment: .leading) { Text(row.username); Text(names[row.scope] ?? row.scope).font(.caption).foregroundStyle(.secondary) }; Spacer(); Button("撤销", role: .destructive) { revoking = row }.disabled(busy) } } }
        }.navigationTitle("访问授权").task { await load() }
            .confirmationDialog("撤销此账号的这项权限？", isPresented: Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } })) { Button("撤销授权", role: .destructive) { if let row = revoking { Task { await remove(row) } }; revoking = nil } }
    }
    private func load() async {
        let context = store.generation
        do { let result: [AccessGrant] = try await store.requireAPI().request("/members/\(member.id)/grants"); guard store.isCurrent(context), !Task.isCancelled else { return }; grants = result }
        catch { if store.isCurrent(context), !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func add() async {
        busy = true; error = nil; let context = store.generation; defer { busy = false }
        do { try await store.requireAPI().send("/members/\(member.id)/grants", method: "POST", body: ["username": username, "scope": scope]); if store.isCurrent(context) { await load(); username = "" } }
        catch { if store.isCurrent(context) { self.error = error.localizedDescription } }
    }
    private func remove(_ row: AccessGrant) async {
        busy = true; error = nil; let context = store.generation; defer { busy = false }
        do { try await store.requireAPI().send("/members/\(member.id)/grants/\(row.id)", method: "DELETE"); if store.isCurrent(context) { await load() } }
        catch { if store.isCurrent(context) { self.error = error.localizedDescription } }
    }
}

struct ShareDocument: Identifiable { let id = UUID(); let url: URL }
struct NativeShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
enum ExportFiles {
    static func create(_ data: Data) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("jiahe-export-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("复诊资料.pdf")
        try data.write(to: file, options: [.atomic, .completeFileProtection])
        return file
    }
    static func remove(_ url: URL) {
        let folder = url.deletingLastPathComponent().standardizedFileURL
        guard folder.lastPathComponent.hasPrefix("jiahe-export-"), folder.deletingLastPathComponent().standardizedFileURL.path == FileManager.default.temporaryDirectory.standardizedFileURL.path else { return }
        try? FileManager.default.removeItem(at: folder)
    }
}
@MainActor
struct VisitExportView: View {
    @EnvironmentObject var store: AppStore
    let member: Member
    @State private var start = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
    @State private var end = Date()
    @State private var indicators = true
    @State private var reports = true
    @State private var busy = false
    @State private var error: String?
    @State private var file: ShareDocument?
    var body: some View {
        Form {
            Section("\(member.name)的复诊资料") {
                DatePicker("开始日期", selection: $start, in: ...end, displayedComponents: .date)
                DatePicker("结束日期", selection: $end, in: start..., displayedComponents: .date)
                Toggle("已入档指标", isOn: $indicators); Toggle("报告目录", isOn: $reports)
                Text("按测量日期和报告日期筛选，包含起止日。未定日期的报告和 Apple 健康摘要不列入。").font(.caption).foregroundStyle(.secondary)
            }
            InlineError(message: error)
            BusyButton(title: "生成 PDF 并选择保存或分享", busy: busy) { Task { await export() } }.disabled(!indicators && !reports)
        }.navigationTitle("导出复诊资料").sheet(item: $file) { document in NativeShareSheet(url: document.url).onDisappear { ExportFiles.remove(document.url) } }
    }
    private func export() async {
        busy = true; error = nil; let context = store.generation; defer { busy = false }
        do {
            let path = "/members/\(member.id)/visit.pdf?start=\(AppDates.day(start))&end=\(AppDates.day(end))&indicators=\(indicators)&report_list=\(reports)"
            let bytes = try await store.requireAPI().bytes(path)
            guard store.isCurrent(context) else { return }; file = ShareDocument(url: try ExportFiles.create(bytes))
        } catch { if store.isCurrent(context) { self.error = error.localizedDescription } }
    }
}
