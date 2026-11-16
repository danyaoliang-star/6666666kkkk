import SwiftUI

@MainActor
struct LifestyleView: View {
    @EnvironmentObject var store: AppStore
    let member: Member
    @State private var context: JSONValue?
    @State private var reportIDs: Set<Int> = []
    @State private var readiness = "unsure"
    @State private var specialCare = false
    @State private var useModel = false
    @State private var advice: JSONValue?
    @State private var selected: Set<String> = []
    @State private var start = Date()
    @State private var confirmed = false
    @State private var busy = false
    @State private var error: String?
    @State private var inputSignature = ""
    private var signature: String { reportIDs.sorted().map(String.init).joined(separator: ",") + readiness + String(specialCare) + String(useModel) }
    var body: some View {
        Form {
            if let context = context {
                Section("选择已确认指标的报告，最多三份") {
                    ForEach(Array(context["reports"].array.filter { $0["confirmed_count"].int > 0 }.enumerated()), id: \.offset) { _, row in
                        Toggle(isOn: Binding(get: { reportIDs.contains(row["id"].int) }, set: { checked in if checked && reportIDs.count < 3 { reportIDs.insert(row["id"].int) } else if !checked { reportIDs.remove(row["id"].int) } })) { Text(row["test_name"].string.isEmpty ? row["name"].string : row["test_name"].string) }
                    }
                    if context["reports"].array.allSatisfy({ $0["confirmed_count"].int == 0 }) { Text("请先在病历夹校对报告指标并入档。").font(.footnote).foregroundStyle(.secondary) }
                }
                Section("核对适用情况") {
                    Picker("当前活动情况", selection: $readiness) { Text("尚不确定").tag("unsure"); Text("日常活动无明显不适").tag("comfortable"); Text("活动受限").tag("limited") }
                    Toggle("存在需遵循专门医嘱的情况", isOn: $specialCare)
                    ForEach(Array(context["memories"].array.enumerated()), id: \.offset) { _, row in Text(row["category"].string + "：" + row["content"].string).font(.caption).foregroundStyle(.secondary) }
                }
                if context["service"]["configured"].bool {
                    Section("模型筛选（可选）") {
                        Text("勾选后会将已确认指标、活动情况和已允许该服务使用的有效健康记忆发送至：" + context["service"]["memory_destination"].string).font(.caption)
                        Toggle("同意发送上述资料，让模型筛选建议", isOn: $useModel)
                    }
                }
                Button("生成饮食与活动建议") { Task { await generate() } }.disabled(busy || reportIDs.isEmpty)
            } else { ProgressView("读取可用资料") }
            InlineError(message: error)
            if let advice = advice {
                Section("建议草稿") {
                    ForEach(Array(advice["warnings"].array.enumerated()), id: \.offset) { _, warning in Text(warning.string).font(.footnote).foregroundStyle(.secondary) }
                    ForEach(Array(advice["actions"].array.enumerated()), id: \.offset) { _, action in
                        VStack(alignment: .leading, spacing: 9) {
                            Toggle(action["title"].string, isOn: Binding(get: { selected.contains(action["id"].string) }, set: { if $0 { selected.insert(action["id"].string) } else { selected.remove(action["id"].string) } }))
                            Text(action["reduce"].string + "\n" + action["alternative"].string + "\n" + action["note"].string).font(.footnote)
                            Text(action["basis"].string).font(.caption).foregroundStyle(.secondary)
                            if let url = URL(string: action["reference"].string), url.scheme == "https" { Link("查看参考资料", destination: url).font(.caption) }
                        }.padding(.vertical, 7)
                    }
                }
                Section("来源与确认") {
                    ForEach(Array(advice["evidence"].array.enumerated()), id: \.offset) { _, row in NavigationLink("\(row["name"].string) \(row["value"].string) \(row["unit"].string) · \(row["measured_at"].string.prefix(10))") { ReportDetailView(member: member, reportID: row["report_id"].int) }.font(.caption) }
                    if advice["state"].string == "confirmed" { Label("已启用七天计划，请返回计划页查看", systemImage: "checkmark.circle") }
                    else {
                        DatePicker("开始日期", selection: $start, displayedComponents: .date)
                        Toggle("我已核对建议和适用情况，确认将所选项保存为连续七天计划。", isOn: $confirmed).font(.footnote)
                        if signature != inputSignature { Text("资料选择已变化，请重新生成建议。").font(.caption).foregroundStyle(.red) }
                        BusyButton(title: "确认并启用七天计划", busy: busy) { Task { await enable() } }.disabled(!confirmed || selected.isEmpty || signature != inputSignature || !member.allows("supervise"))
                    }
                }
            }
        }.disabled(busy).navigationTitle("安排生活计划").task { await load() }
    }
    private func load() async {
        let token = store.generation
        do { let result: JSONValue = try await store.requireAPI().request("/members/\(member.id)/lifestyle"); guard store.isCurrent(token), !Task.isCancelled else { return }; context = result; start = AppDates.date(result["today"].string) }
        catch { if store.isCurrent(token), !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func generate() async {
        busy = true; error = nil; let token = store.generation; let inputs = signature; defer { busy = false }
        do {
            let result: JSONValue = try await store.requireAPI().request("/members/\(member.id)/lifestyle", method: "POST", body: ["report_ids": reportIDs.sorted(), "readiness": readiness, "special_care": specialCare, "use_model": useModel, "destination": useModel ? context?["service"]["memory_destination"].string ?? "" : ""])
            guard store.isCurrent(token) else { return }; advice = result; inputSignature = inputs; selected = Set(result["actions"].array.map { $0["id"].string }); confirmed = false
        } catch { if store.isCurrent(token) { self.error = error.localizedDescription } }
    }
    private func enable() async {
        guard let advice = advice else { return }; busy = true; error = nil; let token = store.generation; defer { busy = false }
        do { let result: JSONValue = try await store.requireAPI().request("/members/\(member.id)/lifestyle/\(advice["id"].int)/confirm", method: "POST", body: ["action_ids": selected.sorted(), "start": AppDates.day(start)]); guard store.isCurrent(token) else { return }; self.advice = result }
        catch { if store.isCurrent(token) { self.error = error.localizedDescription } }
    }
}
