import SwiftUI

@MainActor
struct PlansView: View {
    @EnvironmentObject var store: AppStore
    let member: Member
    @State private var plans: [DailyPlan] = []
    @State private var day = AppDates.date(AppDates.serverToday())
    @State private var editor = false
    @State private var busy = false
    @State private var loading = true
    @State private var error: String?
    var body: some View {
        List {
            if !member.allows("supervise") { EmptyNotice(title: "尚未获得计划监督权限", detail: "请由成员管理者单独授权。", symbol: "lock") }
            else {
                Section {
                    NavigationLink { WeeklyView(member: member) } label: { Label("本周执行回顾", systemImage: "chart.bar.doc.horizontal") }
                    if member.allows("read") && member.allows("write") { NavigationLink { LifestyleView(member: member) } label: { Label("让小康帮我安排生活计划", systemImage: "sparkles") } }
                    DatePicker("打卡日期", selection: $day, in: ...AppDates.date(AppDates.serverToday()), displayedComponents: .date)
                    Text("计划日期按北京时间核对。").font(.caption).foregroundStyle(.secondary)
                }
                InlineError(message: error)
                if loading { ProgressView("读取生活计划") }
                ForEach(plans) { plan in
                    Section {
                        HStack { Text(plan.title).font(.headline); Spacer(); Text(plan.kind).font(.caption).foregroundStyle(AppTheme.accent) }
                        Text("\(plan.start) — \(plan.end)").font(.caption).foregroundStyle(.secondary)
                        if !plan.note.isEmpty { Text(plan.note).font(.footnote) }
                        HStack { Text("\(AppDates.day(day)) · \(plan.state(on: AppDates.day(day)))").font(.footnote); Spacer() }
                        if member.allows("write") {
                            HStack {
                                Button("完成") { Task { await checkin(plan, state: "完成") } }.buttonStyle(.borderedProminent)
                                Button("未完成") { Task { await checkin(plan, state: "未完成") } }.buttonStyle(.bordered)
                            }.disabled(busy || AppDates.day(day) < plan.start || AppDates.day(day) > plan.end)
                        }
                    }
                }
                if plans.isEmpty && !loading { EmptyNotice(title: "还没有生活计划", detail: "制定一个适合自己的小目标，开始记录。", symbol: "calendar") }
            }
        }.navigationTitle("生活计划").task { await load() }.refreshable { await load() }
            .toolbar { if member.allows("write") { Button { editor = true } label: { Image(systemName: "plus") }.accessibilityLabel("制定计划") } }
            .sheet(isPresented: $editor, onDismiss: { Task { await load() } }) { NavigationStack { PlanEditor(member: member) } }
    }
    private func load() async {
        guard member.allows("supervise") else { loading = false; return }; let context = store.generation
        do { let result: [DailyPlan] = try await store.requireAPI().request("/members/\(member.id)/plans"); guard store.isCurrent(context), !Task.isCancelled else { return }; plans = result; error = nil }
        catch { if store.isCurrent(context), !Task.isCancelled { self.error = error.localizedDescription } }
        if store.isCurrent(context) { loading = false }
    }
    private func checkin(_ plan: DailyPlan, state: String) async {
        busy = true; let context = store.generation; defer { busy = false }
        do { try await store.requireAPI().send("/members/\(member.id)/plans/\(plan.id)/logs/\(AppDates.day(day))", method: "PUT", body: ["state": state]); if store.isCurrent(context) { await load() } }
        catch { if store.isCurrent(context) { self.error = error.localizedDescription } }
    }
}

@MainActor
struct PlanEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let member: Member
    @State private var title = ""
    @State private var kind = "运动"
    @State private var start = Date()
    @State private var end = Date()
    @State private var note = ""
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        Form {
            TextField("可执行的小目标", text: $title)
            Picker("类型", selection: $kind) { Text("运动").tag("运动"); Text("饮食").tag("饮食") }
            DatePicker("开始日期", selection: $start, displayedComponents: .date)
            DatePicker("结束日期", selection: $end, in: start..., displayedComponents: .date)
            TextField("执行说明", text: $note, axis: .vertical).lineLimit(3...6)
            Text("确认后，范围内每天各计一次应执行任务。").font(.caption).foregroundStyle(.secondary)
            InlineError(message: error)
            BusyButton(title: "确认并开始执行", busy: busy) { Task { await save() } }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
        }.disabled(busy).navigationTitle("制定计划").navigationBarTitleDisplayMode(.inline).interactiveDismissDisabled(busy)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) } }
    }
    private func save() async {
        busy = true; let context = store.generation; defer { busy = false }
        do { try await store.requireAPI().send("/members/\(member.id)/plans", method: "POST", body: ["title": title, "kind": kind, "start": AppDates.day(start), "end": AppDates.day(end), "note": note]); if store.isCurrent(context) { dismiss() } }
        catch { if store.isCurrent(context) { self.error = error.localizedDescription } }
    }
}

@MainActor
struct WeeklyView: View {
    @EnvironmentObject var store: AppStore
    let member: Member
    @State private var week = AppDates.monday()
    @State private var result: JSONValue?
    @State private var service: JSONValue?
    @State private var consent = false
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        List {
            Section {
                HStack { Button { shift(-7) } label: { Image(systemName: "chevron.left") }; Spacer(); Text(AppDates.day(week)); Spacer(); Button { shift(7) } label: { Image(systemName: "chevron.right") } }.disabled(busy).buttonStyle(.borderless)
                InlineError(message: error)
            }
            if let result = result {
                Section("截至今天已到期的任务") {
                    HStack { stat("完成", result["totals"]["done"].string); stat("未完成", result["totals"]["missed"].string); stat("未填", result["totals"]["blank"].string); stat("完成率", result["totals"]["rate"] == .null ? "—" : result["totals"]["rate"].string + "%") }
                    Text("本周共安排 \(result["totals"]["scheduled"].string) 次，未来日期不计入当前完成率。").font(.caption).foregroundStyle(.secondary)
                }
                if member.allows("write") { Section { NavigationLink("准备或编辑下周计划草稿") { WeeklyDraftView(member: member, sourceWeek: week) } } }
                ForEach(Array(result["plans"].array.enumerated()), id: \.offset) { _, plan in
                    Section(plan["title"].string) { Text("\(plan["kind"].string) · 完成 \(plan["done"].string) / 应执行 \(plan["total"].string)"); ForEach(Array(plan["logs"].array.enumerated()), id: \.offset) { _, log in Text("\(log["day"].string) · \(log["state"].string)").font(.caption) } }
                }
                if service?["configured"].bool == true {
                    Section("小康执行建议") {
                        Text("将本周计划标题、分类和执行统计发送至：\(service?["memory_destination"].string ?? "")").font(.caption)
                        Toggle("我同意发送本周执行资料以生成建议", isOn: $consent)
                        Button("生成执行建议") { Task { await reflect() } }.disabled(!consent || busy)
                        if result["ai"]["stale"].bool { Text("资料已变化，请重新生成。").font(.caption) }
                        ForEach(Array(result["ai"]["suggestions"].array.enumerated()), id: \.offset) { _, row in Text(row["text"].string).font(.footnote) }
                    }
                }
            } else { ProgressView("读取周报") }
        }.navigationTitle("每周回顾").task { await load() }.refreshable { await load() }
    }
    private func stat(_ label: String, _ value: String) -> some View { VStack(spacing: 8) { Text(value).font(.headline); Text(label).font(.caption2).foregroundStyle(.secondary) }.frame(maxWidth: .infinity) }
    private func shift(_ days: Int) { week = Calendar.current.date(byAdding: .day, value: days, to: week)!; result = nil; consent = false; Task { await load() } }
    private func load() async {
        let context = store.generation; let requested = AppDates.day(week)
        do {
            let api = try store.requireAPI()
            let data: JSONValue = try await api.request("/members/\(member.id)/plan-weekly?week=" + requested)
            let model: JSONValue = try await api.request("/assistant/status")
            guard store.isCurrent(context), AppDates.day(week) == requested, !Task.isCancelled else { return }; result = data; service = model; error = nil
        } catch { if store.isCurrent(context), AppDates.day(week) == requested, !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func reflect() async {
        busy = true; let context = store.generation; defer { busy = false }
        do { try await store.requireAPI().send("/members/\(member.id)/plan-weekly/ai", method: "POST", body: ["week": AppDates.day(week), "consent": consent, "destination": service?["memory_destination"].string ?? ""]); if store.isCurrent(context) { await load() } }
        catch { if store.isCurrent(context) { self.error = error.localizedDescription } }
    }
}
