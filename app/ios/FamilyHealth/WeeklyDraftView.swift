import SwiftUI

struct DraftPlanRow: Identifiable {
    let id: Int
    var title: String; var kind: String; var note: String; var start: Date; var end: Date; var included = true
}
@MainActor
struct WeeklyDraftView: View {
    @EnvironmentObject var store: AppStore
    let member: Member; let sourceWeek: Date
    @State private var draft: JSONValue?
    @State private var rows: [DraftPlanRow] = []
    @State private var checked = false
    @State private var busy = false
    @State private var error: String?
    @State private var notice: String?
    private var first: Date { Calendar.current.date(byAdding: .day, value: 7, to: sourceWeek)! }
    private var last: Date { Calendar.current.date(byAdding: .day, value: 13, to: sourceWeek)! }
    var body: some View {
        Form {
            Section("下一周 · \(AppDates.day(first)) — \(AppDates.day(last))") {
                Text("根据本周计划准备未覆盖的下周日期。草稿经你核对并确认后生效。").font(.footnote).foregroundStyle(.secondary)
                if draft == nil { Button("准备下周计划草稿") { Task { await prepare() } }.disabled(busy) }
                if let notice = notice { Text(notice).font(.footnote) }
                InlineError(message: error)
            }
            if let draft = draft {
                if draft["state"].string == "confirmed" { Label("这批计划已确认生效", systemImage: "checkmark.circle") }
                else {
                    ForEach($rows) { $row in
                        Section {
                            Toggle("保留这项计划", isOn: $row.included)
                            TextField("计划名称", text: $row.title)
                            Picker("类型", selection: $row.kind) { Text("运动").tag("运动"); Text("饮食").tag("饮食") }
                            DatePicker("开始", selection: $row.start, in: first...last, displayedComponents: .date)
                            DatePicker("结束", selection: $row.end, in: first...last, displayedComponents: .date)
                            TextField("执行说明", text: $row.note, axis: .vertical)
                        }.disabled(busy)
                    }
                    Toggle("我已核对所选计划、日期和执行说明，确认生效。", isOn: $checked).font(.footnote)
                    Button("仅保存草稿") { Task { await save(confirm: false) } }.disabled(busy || !rows.contains { $0.included })
                    BusyButton(title: "保存并确认下周计划", busy: busy) { Task { await save(confirm: true) } }.disabled(!checked || !rows.contains { $0.included })
                    Button("重新读取草稿") { Task { await load() } }.disabled(busy)
                }
            }
        }.navigationTitle("下周计划草稿").task { await load() }
    }
    private func assign(_ data: JSONValue) {
        draft = data
        rows = data["items"].array.map { DraftPlanRow(id: $0["source_plan_id"].int, title: $0["title"].string, kind: $0["kind"].string, note: $0["note"].string, start: AppDates.date($0["start"].string), end: AppDates.date($0["end"].string)) }
        checked = false
    }
    private func load() async {
        let token = store.generation
        do { let data: JSONValue = try await store.requireAPI().request("/members/\(member.id)/plan-weekly?week=" + AppDates.day(sourceWeek)); guard store.isCurrent(token), !Task.isCancelled else { return }; if data["draft"] != .null { assign(data["draft"]) } }
        catch { if store.isCurrent(token), !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func prepare() async {
        busy = true; error = nil; let token = store.generation; defer { busy = false }
        do { let data: JSONValue = try await store.requireAPI().request("/members/\(member.id)/plan-weekly/drafts", method: "POST", body: ["week": AppDates.day(sourceWeek)]); if store.isCurrent(token) { assign(data) } }
        catch { if store.isCurrent(token) { self.error = error.localizedDescription } }
    }
    private func save(confirm: Bool) async {
        guard let draft = draft else { return }; busy = true; error = nil; let token = store.generation; defer { busy = false }
        do {
            let items: [[String: Any]] = rows.filter(\.included).map { ["source_plan_id": $0.id, "title": $0.title, "kind": $0.kind, "note": $0.note, "start": AppDates.day($0.start), "end": AppDates.day($0.end)] }
            let api = try store.requireAPI()
            let base = "/members/\(member.id)/plan-weekly/drafts/\(draft["id"].int)"
            let saved: JSONValue = try await api.request(base, method: "PUT", body: ["revision": draft["revision"].int, "items": items])
            guard store.isCurrent(token) else { return }; self.draft = saved
            if confirm {
                let enabled: JSONValue = try await api.request(base + "/confirm", method: "POST", body: ["revision": saved["revision"].int])
                guard store.isCurrent(token) else { return }; assign(enabled); notice = "已启用下周计划，可返回计划页查看。"
            } else { notice = "草稿已保存。" }
        } catch { if store.isCurrent(token) { self.error = error.localizedDescription } }
    }
}
