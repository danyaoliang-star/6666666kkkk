import SwiftUI
import Charts

@MainActor
struct HealthHomeView: View {
    @EnvironmentObject var store: AppStore
    let member: Member
    @State private var connection: HealthConnection?
    @State private var observations: [Observation] = []
    @State private var care: CareOverview?
    @State private var loading = true
    @State private var error: String?
    @State private var detail: HealthScope?
    private var today: String { connection?.windowEnd ?? AppDates.day() }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !member.allows("read") { EmptyNotice(title: "尚未获得健康资料查看权限", detail: "可在「计划」查看获授权的执行情况。", symbol: "lock.shield") }
                else {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) { Text("DAILY WELLNESS").font(.caption2).tracking(2).foregroundStyle(.secondary); Text("照顾好每一天。").font(.title2.bold()) }
                        Spacer()
                        NavigationLink { HealthDeviceView(member: member) } label: { Image(systemName: "slider.horizontal.3").padding(12).background(.white, in: Circle()) }.accessibilityLabel("设备与授权")
                    }
                    if loading { ProgressView("正在读取健康档案") }
                    InlineError(message: error)
                    HealthCard {
                        VStack(spacing: 22) {
                            HStack { Text(today == AppDates.day() ? "今天 · \(member.name)" : today); Spacer(); Text(connection?.active == true ? "Apple 健康" : "等待记录") }.font(.caption).foregroundStyle(.secondary)
                            HStack(spacing: 12) {
                                ForEach([HealthScope.activeEnergy, .exerciseTime, .sleep]) { scope in
                                    Button { detail = scope } label: {
                                        VStack(spacing: 11) {
                                            ZStack {
                                                Circle().stroke(scope.color.opacity(reading(scope) == nil ? 0.12 : 0.45), lineWidth: 8)
                                                VStack(spacing: 4) { Text(displayNumber(reading(scope))).font(.title3.bold()).minimumScaleFactor(0.6); Text(reading(scope) == nil ? "待同步" : scope.unit).font(.caption2).foregroundStyle(.secondary) }
                                            }.aspectRatio(1, contentMode: .fit)
                                            Text(scope.name).font(.caption).foregroundStyle(scope.color)
                                        }
                                    }.buttonStyle(.plain)
                                }
                            }
                            Divider()
                            Label("由你选择分享哪些数据，随时可以停止同步。", systemImage: "heart").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink { HealthDeviceView(member: member) } label: {
                        HealthCard { HStack(spacing: 12) { Image(systemName: "heart.fill").foregroundStyle(.pink).font(.title2); VStack(alignment: .leading, spacing: 5) { Text(connection?.active == true ? "管理 Apple 健康" : "连接 Apple 健康").fontWeight(.semibold); Text(connection?.lastSyncedAt == nil ? "在系统授权后同步健康摘要" : "上次同步 " + String(connection!.lastSyncedAt!.prefix(16)).replacingOccurrences(of: "T", with: " ")).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").font(.caption) } }
                    }.buttonStyle(.plain)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        ForEach([HealthScope.steps, .heartRate, .bodyMass]) { scope in
                            Button { detail = scope } label: {
                                HealthCard { VStack(alignment: .leading, spacing: 16) {
                                    Label(scope.name, systemImage: scope.symbol).font(.subheadline).foregroundStyle(scope.color)
                                    Text(displayNumber(reading(scope))).font(.title.bold())
                                    Text(reading(scope) == nil ? "暂无可读取记录" : scope.unit + " · " + scope.explanation).font(.caption2).foregroundStyle(.secondary)
                                } }
                            }.buttonStyle(.plain)
                        }
                        NavigationLink { RecordsView(member: member) } label: { HealthCard { VStack(alignment: .leading, spacing: 16) { Label("健康记录", systemImage: "waveform.path.ecg").font(.subheadline); Text("记录变化").font(.title3.bold()); Text("血压、血糖与检查指标").font(.caption2).foregroundStyle(.secondary) } } }.buttonStyle(.plain)
                    }
                    if let care = care, !care.reminders.isEmpty {
                        HealthCard { VStack(alignment: .leading, spacing: 12) {
                            Text("复查提醒").font(.headline)
                            ForEach(care.reminders.prefix(4)) { row in HStack { Text(row.title); Spacer(); Text(row.dueDate).foregroundStyle(row.daysUntil < 0 ? .red : .secondary) }.font(.footnote) }
                            NavigationLink("管理目标与复查") { CareView(member: member) }
                        } }
                    }
                    HealthCard { VStack(spacing: 16) {
                        NavigationLink { ReportsView(member: member) } label: { Label("病历夹与报告校对", systemImage: "folder.badge.plus") }
                        Divider()
                        NavigationLink { TrendView(member: member, records: observations) } label: { Label("健康指标趋势", systemImage: "chart.xyaxis.line") }
                        Divider()
                        NavigationLink { CareView(member: member) } label: { Label("慢病目标与复查", systemImage: "calendar.badge.clock") }
                    }.frame(maxWidth: .infinity, alignment: .leading) }
                    Text("日常健康摘要与检查指标分别保存，空值表示暂无可读取数据。").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(20)
        }.appBackground().task { await load() }.refreshable { await load() }
            .sheet(item: $detail) { scope in NavigationStack { HealthHistoryView(scope: scope, connection: connection) } }
    }
    private func reading(_ scope: HealthScope) -> Double? { connection?.records.first { $0.code == scope && $0.day == today }?.value }
    private func load() async {
        guard member.allows("read") else { loading = false; return }; let context = store.generation
        loading = true; error = nil
        defer { if store.isCurrent(context) { loading = false } }
        do {
            let api = try store.requireAPI()
            let health: HealthConnection = try await api.request("/members/\(member.id)/apple-health")
            let records: [Observation] = try await api.request("/members/\(member.id)/observations")
            let careResult: CareOverview = try await api.request("/members/\(member.id)/care")
            guard store.isCurrent(context), !Task.isCancelled else { return }
            connection = health; observations = records; care = careResult
        } catch { if store.isCurrent(context), !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

struct HealthHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    let scope: HealthScope; let connection: HealthConnection?
    private var records: [HealthReading] { connection?.records.filter { $0.code == scope }.sorted { $0.day < $1.day } ?? [] }
    var body: some View {
        List {
            Section {
                if records.isEmpty { EmptyNotice(title: "暂无可读取记录", detail: "在设备页连接 Apple 健康后同步。未允许读取和没有记录都会显示为空。", symbol: scope.symbol) }
                else {
                    Chart(records) { row in BarMark(x: .value("日期", AppDates.date(row.day), unit: .day), y: .value(scope.unit, row.value)).foregroundStyle(scope.color.gradient) }.frame(height: 200)
                    ForEach(records.reversed()) { row in HStack { Text(row.day); Spacer(); Text(displayNumber(row.value) + " " + scope.unit) } }
                }
            } header: { Text("最近七天") } footer: { Text(scope.explanation + "。时区：" + (connection?.timezone ?? "设备当地时间")) }
        }.navigationTitle(scope.name).toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
    }
}

@MainActor
struct HealthDeviceView: View {
    @EnvironmentObject var store: AppStore
    let member: Member
    @State private var connection: HealthConnection?
    @State private var editor = false
    @State private var selected: Set<HealthScope> = [.steps, .activeEnergy, .exerciseTime]
    @State private var accepted = false
    @State private var busy = false
    @State private var error: String?
    @State private var notice: String?
    @State private var revoke = false
    var body: some View {
        List {
            Section {
                HStack { VStack(alignment: .leading, spacing: 8) { Text("Apple 健康").font(.title3.bold()); Label(connection?.active == true ? "已开启同步许可" : "尚未连接", systemImage: connection?.active == true ? "checkmark.circle.fill" : "circle").font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "heart.fill").font(.largeTitle).foregroundStyle(.pink) }
                if let connection = connection {
                    if connection.active { Text(connection.scopes.map(\.name).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
                    if let time = connection.lastSyncedAt { Text("上次同步：" + time).font(.caption2).foregroundStyle(.secondary) }
                    Button(connection.active ? "管理同步范围" : "连接与授权") { selected = connection.active ? Set(connection.scopes) : [.steps, .activeEnergy, .exerciseTime]; accepted = false; error = nil; editor = true }
                        .disabled(busy || !connection.canConnect || !HealthKitService.shared.available)
                    if !connection.canConnect { Text("请切换到当前账号管理、关系为“本人”的档案，连接自己的健康数据。").font(.footnote).foregroundStyle(.secondary) }
                    if connection.active {
                        Button { Task { await synchronize() } } label: { Label(busy ? "正在同步…" : "立即同步", systemImage: "arrow.triangle.2.circlepath") }.disabled(busy || !connection.canConnect)
                        Button("停止同步并删除摘要", role: .destructive) { revoke = true }.disabled(busy)
                    }
                } else { ProgressView("读取同步状态") }
                if !HealthKitService.shared.available { Text("当前设备不支持健康数据。请在支持 HealthKit 的 iPhone 上运行。").font(.footnote).foregroundStyle(.secondary) }
                InlineError(message: error)
                if let notice = notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
            }
            Section("数据分享，由你决定") {
                Text("只读取你选择且系统允许的数据。最近七天摘要会保存至当前家和服务，仅本人账号查看，不随家人查看权限共享，也不进入小康模型问答。")
                Text("无数据和未允许读取均显示为空，系统不会向 App 披露单项读取权限是否被拒绝。")
                Text("如需撤销系统读取权限，请打开 iPhone「健康 → 个人头像 → App 和服务 → 家和」。")
            }.font(.footnote).foregroundStyle(.secondary)
            Section("设备数据") { Label("手表、手环和体脂秤", systemImage: "applewatch"); Text("请先在设备配套 App 中开启 Apple 健康共享，再在这里授权与同步。当前不直接配对蓝牙设备。").font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle("设备与授权").task { await load() }.refreshable { await load() }
            .confirmationDialog("停止同步会删除本系统的 Apple 健康摘要，iPhone 健康中的原始记录会保留。", isPresented: $revoke, titleVisibility: .visible) {
                Button("停止同步并删除摘要", role: .destructive) { Task { await disconnect() } }
            }
            .sheet(isPresented: $editor) { consentSheet.interactiveDismissDisabled(busy) }
    }
    private var consentSheet: some View {
        NavigationStack {
            Form {
                Section("选择要读取的数据") {
                    ForEach(HealthScope.allCases) { scope in
                        Toggle(isOn: Binding(get: { selected.contains(scope) }, set: { if $0 { selected.insert(scope) } else { selected.remove(scope) } })) {
                            VStack(alignment: .leading, spacing: 4) { Label(scope.name, systemImage: scope.symbol); Text(scope.explanation).font(.caption).foregroundStyle(.secondary) }
                        }.disabled(busy)
                    }
                }
                Section("确认数据归属与保存") {
                    Text("保存至：\(member.name)的本人档案")
                    Text("接收服务器：\(store.api?.server.host ?? "")").font(.footnote)
                    Toggle("我确认这是本人档案，同意读取所选项目并将最近七天摘要保存至上述服务。", isOn: $accepted).font(.footnote).disabled(busy)
                    Text("接下来会显示 iOS 系统授权。你仍可逐项决定；仅完成流程不代表所有项目已允许读取。").font(.caption).foregroundStyle(.secondary)
                    InlineError(message: error)
                    BusyButton(title: "同意并继续系统授权", busy: busy) { Task { await connect() } }.disabled(!accepted || selected.isEmpty)
                }
            }.navigationTitle("连接 Apple 健康").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { editor = false }.disabled(busy) } }
        }
    }
    private func load() async {
        let context = store.generation
        do { let result: HealthConnection = try await store.requireAPI().request("/members/\(member.id)/apple-health"); guard store.isCurrent(context), !Task.isCancelled else { return }; connection = result }
        catch { if store.isCurrent(context), !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func check(_ context: UUID) throws { try Task.checkCancellation(); guard store.isCurrent(context), store.member?.id == member.id else { throw ClientError.staleContext } }
    private func connect() async {
        guard !busy, accepted, !selected.isEmpty else { return }; busy = true; error = nil; notice = nil
        let context = store.generation; defer { busy = false }
        do {
            let scopes = HealthScope.allCases.filter { selected.contains($0) }
            try await HealthKitService.shared.authorize(scopes); try check(context)
            let result: HealthConnection = try await store.requireAPI().request("/members/\(member.id)/apple-health", method: "PUT", body: ["scopes": scopes.map(\.rawValue), "consent": true, "is_self": true, "policy_version": "2026-11-16"])
            try check(context); connection = result; editor = false
            try await upload(context)
        } catch { if store.isCurrent(context) { self.error = error.localizedDescription } }
    }
    private func upload(_ context: UUID) async throws {
        guard let connection = connection, let consentID = connection.consentId, connection.active else { return }
        let snapshot = try await HealthKitService.shared.snapshot(connection.scopes); try check(context)
        let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
        var body = try JSONSerialization.jsonObject(with: encoder.encode(snapshot)) as! [String: Any]
        body["consent_id"] = consentID
        let result: HealthConnection = try await store.requireAPI().request("/members/\(member.id)/apple-health/sync", method: "POST", body: body)
        try check(context); self.connection = result
        notice = snapshot.records.isEmpty ? "暂未读取到数据。请在 iPhone「健康」中检查记录和读取权限。" : "已同步最近七天可读取的健康摘要。"
    }
    private func synchronize() async {
        guard !busy else { return }; busy = true; error = nil; notice = nil
        let context = store.generation; defer { busy = false }
        do { try await upload(context) } catch { if store.isCurrent(context) { self.error = error.localizedDescription } }
    }
    private func disconnect() async {
        guard !busy else { return }; busy = true; error = nil
        let context = store.generation; defer { busy = false }
        do { try await store.requireAPI().send("/members/\(member.id)/apple-health", method: "DELETE"); try check(context); connection = nil; await load(); notice = "已停止同步并删除本系统摘要。系统读取权限请在 iPhone「健康」中关闭。" }
        catch { if store.isCurrent(context) { self.error = error.localizedDescription } }
    }
}
