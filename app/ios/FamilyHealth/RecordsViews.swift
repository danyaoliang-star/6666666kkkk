import SwiftUI
import Charts

@MainActor
struct RecordsView: View {
    @EnvironmentObject var store: AppStore
    let member: Member
    @State private var records: [Observation] = []
    @State private var filter = ""
    @State private var editor = false
    @State private var error: String?
    @State private var loading = true
    var body: some View {
        List {
            if !member.allows("read") { EmptyNotice(title: "没有资料查看权限", symbol: "lock") }
            else {
                Section { Picker("指标", selection: $filter) { Text("全部指标").tag(""); ForEach(store.catalog.keys.sorted(), id: \.self) { code in Text(store.catalog[code]!.name + "（" + store.catalog[code]!.unit + "）").tag(code) } } }
                InlineError(message: error)
                if loading { ProgressView("读取记录") }
                ForEach(records.filter { filter.isEmpty || $0.code == filter }) { row in
                    VStack(alignment: .leading, spacing: 9) {
                        HStack { Text(store.catalog[row.code]?.name ?? row.code).font(.headline); Spacer(); Text(displayNumber(row.value) + " " + (store.catalog[row.code]?.unit ?? "")).fontWeight(.semibold) }
                        Text(row.measuredAt.replacingOccurrences(of: "T", with: " ") + " · " + row.condition).font(.caption).foregroundStyle(.secondary)
                        if !row.note.isEmpty { Text(row.note).font(.footnote) }
                        if let reportID = row.reportId { NavigationLink("查看来源报告 #\(reportID)") { ReportDetailView(member: member, reportID: reportID) }.font(.caption) }
                        else { Text("手动录入 #\(row.id)").font(.caption2).foregroundStyle(.secondary) }
                    }.padding(.vertical, 7)
                }
                if !loading && records.isEmpty { EmptyNotice(title: "暂无指标记录", detail: "可手动录入，或从病历报告中校对入档。") }
            }
        }.navigationTitle("健康记录").refreshable { await load() }.task { await load() }
            .toolbar { if member.allows("write") { Button { editor = true } label: { Image(systemName: "plus") }.accessibilityLabel("录入健康数据") } }
            .sheet(isPresented: $editor, onDismiss: { Task { await load() } }) { NavigationStack { RecordEditor(member: member) } }
    }
    private func load() async {
        guard member.allows("read") else { loading = false; return }; let context = store.generation
        do { let rows: [Observation] = try await store.requireAPI().request("/members/\(member.id)/observations"); guard store.isCurrent(context), !Task.isCancelled else { return }; records = rows; error = nil }
        catch { if store.isCurrent(context), !Task.isCancelled { self.error = error.localizedDescription } }
        if store.isCurrent(context) { loading = false }
    }
}

@MainActor
struct RecordEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let member: Member
    @State private var code = "sbp"
    @State private var value = ""
    @State private var measured = Date()
    @State private var condition = "晨起"
    @State private var low = ""
    @State private var high = ""
    @State private var note = ""
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        Form {
            Section("\(member.name)的测量记录") {
                Picker("指标", selection: $code) { ForEach(store.catalog.keys.sorted(), id: \.self) { key in Text(store.catalog[key]!.name + "（" + store.catalog[key]!.unit + "）").tag(key) } }
                TextField("测量结果", text: $value).keyboardType(.decimalPad)
                DatePicker("测量时间", selection: $measured, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                TextField("测量条件，如空腹、晨起", text: $condition)
            }
            Section("报告参考范围（选填）") { TextField("下限", text: $low).keyboardType(.decimalPad); TextField("上限", text: $high).keyboardType(.decimalPad) }
            Section("备注") { TextField("选填", text: $note, axis: .vertical).lineLimit(3...6) }
            InlineError(message: error)
            BusyButton(title: "确认并保存", busy: busy) { Task { await save() } }
        }.disabled(busy).navigationTitle("录入指标").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) } }.interactiveDismissDisabled(busy)
    }
    private func save() async {
        guard let number = Double(value), number.isFinite, number > 0, !condition.trimmingCharacters(in: .whitespaces).isEmpty else { error = "请填写大于零的数值和测量条件。"; return }
        guard (low.isEmpty || Double(low) != nil), (high.isEmpty || Double(high) != nil) else { error = "请核对参考范围。"; return }
        busy = true; error = nil; let context = store.generation; defer { busy = false }
        do {
            try await store.requireAPI().send("/members/\(member.id)/observations", method: "POST", body: ["code": code, "value": number, "measured_at": AppDates.timestamp(measured), "condition": condition, "note": note, "ref_low": Double(low).map { $0 as Any } ?? NSNull(), "ref_high": Double(high).map { $0 as Any } ?? NSNull()])
            if store.isCurrent(context) { dismiss() }
        } catch { if store.isCurrent(context) { self.error = error.localizedDescription } }
    }
}

@MainActor
struct TrendView: View {
    @EnvironmentObject var store: AppStore
    let member: Member
    var records: [Observation] = []
    @State private var loaded: [Observation] = []
    @State private var code = "ldl"
    @State private var condition = ""
    @State private var error: String?
    private var conditions: [String] { Array(Set(loaded.filter { $0.code == code }.map(\.condition))).sorted() }
    private var rows: [Observation] { loaded.filter { $0.code == code && $0.condition == condition }.sorted { $0.measuredAt < $1.measuredAt } }
    private var comparable: Bool { !["", "未注明", "未知"].contains(condition) }
    var body: some View {
        List {
            Section {
                Picker("指标", selection: $code) { ForEach(store.catalog.keys.sorted(), id: \.self) { key in Text(store.catalog[key]!.name + "（" + store.catalog[key]!.unit + "）").tag(key) } }
                Picker("测量条件", selection: $condition) { ForEach(conditions, id: \.self) { Text($0).tag($0) } }
                InlineError(message: error)
                if rows.isEmpty { EmptyNotice(title: "暂无此条件下的记录") }
                else {
                    Chart(rows) { row in
                        PointMark(x: .value("测量日期", AppDates.measurement(row.measuredAt)), y: .value("结果", row.value)).foregroundStyle(AppTheme.accent)
                        if comparable { LineMark(x: .value("测量日期", AppDates.measurement(row.measuredAt)), y: .value("结果", row.value)).foregroundStyle(AppTheme.accent.opacity(0.5)) }
                    }.frame(height: 230).chartYScale(domain: .automatic(includesZero: false))
                    Text(summary).font(.footnote).foregroundStyle(.secondary)
                }
            } header: { Text("同指标、同条件比较") }
            Section("来源记录") {
                ForEach(rows.reversed()) { row in VStack(alignment: .leading, spacing: 6) {
                    Text("\(row.measuredAt) · \(displayNumber(row.value)) \(store.catalog[code]?.unit ?? "")").font(.footnote)
                    if let id = row.reportId { NavigationLink("报告 #\(id)") { ReportDetailView(member: member, reportID: id) }.font(.caption) }
                    else { Text("手动记录 #\(row.id)").font(.caption).foregroundStyle(.secondary) }
                } }
            }
        }.navigationTitle("指标趋势").onChange(of: code) { _ in condition = conditions.first ?? "" }
            .task { loaded = records; condition = conditions.first ?? ""; await load() }.refreshable { await load() }
    }
    private var summary: String {
        guard comparable else { return "未注明测量条件，仅展示记录，不计算可比变化。" }
        guard rows.count >= 2, let first = rows.first, let last = rows.last else { return "至少两条同条件记录才能比较变化。" }
        let difference = last.value - first.value
        return "从 \(first.measuredAt.prefix(10)) 到 \(last.measuredAt.prefix(10))，由 \(displayNumber(first.value)) 变为 \(displayNumber(last.value))，\(difference >= 0 ? "增加" : "减少") \(displayNumber(abs(difference))) \(store.catalog[code]?.unit ?? "")。"
    }
    private func load() async {
        let context = store.generation
        do { let rows: [Observation] = try await store.requireAPI().request("/members/\(member.id)/observations"); guard store.isCurrent(context), !Task.isCancelled else { return }; loaded = rows; if !conditions.contains(condition) { condition = conditions.first ?? "" }; error = nil }
        catch { if store.isCurrent(context), !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

@MainActor
struct CareView: View {
    @EnvironmentObject var store: AppStore
    let member: Member
    @State private var overview: CareOverview?
    @State private var editor = false
    @State private var isGoal = true
    @State private var goal: CareGoal?
    @State private var followup: Followup?
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        List {
            InlineError(message: error)
            Section("医生给出的指标目标") {
                if overview?.goals.isEmpty == true { Text("暂无目标，请按已有医嘱记录。").foregroundStyle(.secondary) }
                ForEach(overview?.goals ?? []) { row in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text(row.name).font(.headline); Spacer(); Text(row.state == "active" ? "生效中" : "已停用").font(.caption).foregroundStyle(.secondary) }
                        Text("\(row.low.map { displayNumber($0) } ?? "未列下限") — \(row.high.map { displayNumber($0) } ?? "未列上限") \(row.unit)")
                        Text(row.condition + " · " + row.goalDate + " · " + row.source).font(.caption).foregroundStyle(.secondary)
                        if let latest = row.latest { Text("最近记录：\(displayNumber(latest.value)) \(row.unit) · \(latest.measuredAt.prefix(10))").font(.footnote) }
                        if overview?.canWrite == true { Button("编辑目标") { goal = row; followup = nil; isGoal = true; editor = true }.font(.caption) }
                    }.padding(.vertical, 5)
                }
                if overview?.canWrite == true { Button("记录医生目标") { goal = nil; followup = nil; isGoal = true; editor = true } }
            }
            Section("复查安排") {
                ForEach(overview?.followups ?? []) { row in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text(row.title).font(.headline); Spacer(); Text(row.state == "done" ? "已完成" : row.state == "cancelled" ? "已取消" : row.daysUntil < 0 ? "已逾期" : "待复查").font(.caption) }
                        Text(row.dueDate + " · " + row.note).font(.footnote).foregroundStyle(.secondary)
                        if overview?.canWrite == true {
                            HStack {
                                Button("编辑") { followup = row; goal = nil; isGoal = false; editor = true }
                                Spacer()
                                Button(row.state == "done" ? "恢复待办" : "标记完成") { Task { await change(row) } }.disabled(busy)
                            }.font(.caption).buttonStyle(.borderless)
                        }
                    }.padding(.vertical, 5)
                }
                if overview?.canWrite == true { Button("安排复查") { followup = nil; goal = nil; isGoal = false; editor = true } }
            }
        }.navigationTitle("目标与复查").task { await load() }.refreshable { await load() }
            .sheet(isPresented: $editor, onDismiss: { Task { await load() } }) { NavigationStack { CareEditor(member: member, isGoal: isGoal, goal: goal, followup: followup) } }
    }
    private func load() async {
        let context = store.generation
        do { let result: CareOverview = try await store.requireAPI().request("/members/\(member.id)/care"); guard store.isCurrent(context), !Task.isCancelled else { return }; overview = result; error = nil }
        catch { if store.isCurrent(context), !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func change(_ row: Followup) async {
        busy = true; let context = store.generation; defer { busy = false }
        do { try await store.requireAPI().send("/members/\(member.id)/care/followups/\(row.id)", method: "PUT", body: ["title": row.title, "due_date": row.dueDate, "note": row.note, "state": row.state == "done" ? "pending" : "done", "revision": row.revision]); if store.isCurrent(context) { await load() } }
        catch { if store.isCurrent(context) { self.error = error.localizedDescription; await load() } }
    }
}

@MainActor
struct CareEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let member: Member; let isGoal: Bool; let goal: CareGoal?; let followup: Followup?
    @State private var title = ""
    @State private var code = "ldl"
    @State private var low = ""
    @State private var high = ""
    @State private var condition = "空腹"
    @State private var source = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var state = "active"
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        Form {
            if isGoal {
                Picker("指标", selection: $code) { ForEach(store.catalog.keys.sorted(), id: \.self) { Text(store.catalog[$0]!.name).tag($0) } }
                TextField("目标下限（选填）", text: $low).keyboardType(.decimalPad)
                TextField("目标上限（选填）", text: $high).keyboardType(.decimalPad)
                TextField("测量条件", text: $condition)
                TextField("医嘱来源", text: $source, axis: .vertical)
                DatePicker("目标记录日期", selection: $date, in: ...Date(), displayedComponents: .date)
                Picker("状态", selection: $state) { Text("生效").tag("active"); Text("停用").tag("archived") }
            } else {
                TextField("复查事项", text: $title)
                DatePicker("复查日期", selection: $date, displayedComponents: .date)
                TextField("准备事项", text: $note, axis: .vertical)
                Picker("状态", selection: $state) { Text("待复查").tag("pending"); Text("已完成").tag("done"); Text("已取消").tag("cancelled") }
            }
            InlineError(message: error)
            BusyButton(title: "保存", busy: busy) { Task { await save() } }
        }.disabled(busy).navigationTitle(isGoal ? "记录医生目标" : "安排复查").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) } }.interactiveDismissDisabled(busy)
            .onAppear {
                if let row = goal { code = row.code; low = row.low.map { String($0) } ?? ""; high = row.high.map { String($0) } ?? ""; condition = row.condition; source = row.source; date = AppDates.date(row.goalDate); state = row.state }
                else if let row = followup { title = row.title; date = AppDates.date(row.dueDate); note = row.note; state = row.state }
                else { state = isGoal ? "active" : "pending" }
            }
    }
    private func save() async {
        busy = true; error = nil; let context = store.generation; defer { busy = false }
        do {
            var body: [String: Any]
            if isGoal {
                guard (low.isEmpty || Double(low) != nil), (high.isEmpty || Double(high) != nil) else { throw ClientError.server(422, "请核对目标数值。") }
                body = ["code": code, "low": Double(low).map { $0 as Any } ?? NSNull(), "high": Double(high).map { $0 as Any } ?? NSNull(), "condition": condition, "source": source, "goal_date": AppDates.day(date), "state": state]
            } else { body = ["title": title, "due_date": AppDates.day(date), "note": note, "state": state] }
            let id = isGoal ? goal?.id : followup?.id
            if let revision = isGoal ? goal?.revision : followup?.revision { body["revision"] = revision }
            try await store.requireAPI().send("/members/\(member.id)/care/" + (isGoal ? "goals" : "followups") + (id.map { "/\($0)" } ?? ""), method: id == nil ? "POST" : "PUT", body: body)
            if store.isCurrent(context) { dismiss() }
        } catch { if store.isCurrent(context) { self.error = error.localizedDescription } }
    }
}
