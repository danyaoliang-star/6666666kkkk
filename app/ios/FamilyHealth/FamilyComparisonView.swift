import SwiftUI

@MainActor
struct FamilyComparisonView: View {
    @EnvironmentObject var store: AppStore
    @State private var selected: Set<Int> = []
    @State private var choices: [String: Int] = [:]
    @State private var result: JSONValue?
    @State private var busy = false
    @State private var error: String?
    @State private var relationship: RelationshipSelection?
    @State private var sourceSignature = ""
    private var available: [Member] { store.members.filter { $0.allows("read") } }
    private var signature: String { selected.sorted().map(String.init).joined(separator: ",") + choices.keys.sorted().map { $0 + ":" + String(choices[$0]!) }.joined(separator: ",") }
    var body: some View {
        List {
            Section("选择 2–6 位拥有查看权限的家人") {
                ForEach(available) { member in
                    Toggle(member.name, isOn: Binding(get: { selected.contains(member.id) }, set: { checked in
                        if checked && selected.count < 6 { selected.insert(member.id) } else if !checked { selected.remove(member.id) }
                        choices = [:]; result = nil
                    })).disabled(busy)
                }
                Button("对照 Lp(a) 记录") { Task { await compare() } }.disabled(selected.count < 2 || busy)
                InlineError(message: error)
            }
            if let result = result {
                ForEach(Array(result["members"].array.enumerated()), id: \.offset) { _, person in
                    Section(person["name"].string) {
                        Text(person["note"].string).font(.footnote).foregroundStyle(.secondary)
                        if person["record"] != .null {
                            let record = person["record"]
                            Text("\(record["value"].string) \(record["unit"].string)").font(.title3.bold())
                            Text(record["measured_at"].string + " · " + record["condition"].string).font(.caption).foregroundStyle(.secondary)
                            Text(record["assessment"]["lab_label"].string + "\n" + record["assessment"]["risk_label"].string).font(.footnote)
                            recordSource(person: person, record: record)
                        }
                        if !person["options"].array.isEmpty {
                            Picker("选择来源记录", selection: Binding(get: { choices[String(person["id"].int)] ?? person["record"]["id"].int }, set: { value in if value == 0 { choices.removeValue(forKey: String(person["id"].int)) } else { choices[String(person["id"].int)] = value } })) {
                                Text("请选择来源记录").tag(0)
                                ForEach(Array(person["options"].array.enumerated()), id: \.offset) { _, option in Text("\(option["measured_at"].string.prefix(10)) · \(option["value"].string) \(option["unit"].string)").tag(option["id"].int) }
                            }.disabled(busy)
                        }
                    }
                }
                if sourceSignature != signature { Section { Text("来源选择已变化，请点击上方对照按钮更新。").foregroundStyle(.secondary) } }
                else {
                    Section("关系核实") {
                        Text("称呼或同属一个家庭不能自动作为血缘证据。").font(.caption).foregroundStyle(.secondary)
                        ForEach(Array(result["relationships"].array.enumerated()), id: \.offset) { _, pair in
                            let label = memberName(pair["first_member_id"].int) + " / " + memberName(pair["second_member_id"].int)
                            VStack(alignment: .leading, spacing: 7) {
                                Text(label)
                                Text(result["relationship_options"][pair["kind"].string].string).font(.caption).foregroundStyle(.secondary)
                                if pair["can_edit"].bool { Button("核实或修改关系") { relationship = RelationshipSelection(pair: pair, options: result["relationship_options"]) }.font(.caption) }
                            }
                        }
                    }
                    Section("记录提示") {
                        ForEach(Array(result["signals"].array.enumerated()), id: \.offset) { _, signal in VStack(alignment: .leading, spacing: 10) { Text(signal["title"].string).font(.headline); Text(signal["text"].string).font(.footnote); Text(signal["next_step"].string).font(.footnote); Text(signal["unit_note"].string).font(.caption).foregroundStyle(.secondary) } }
                        Text(result["note"].string).font(.caption).foregroundStyle(.secondary)
                    }
                    Section("参考资料") { ForEach(Array(result["references"].array.enumerated()), id: \.offset) { _, row in if let url = URL(string: row["url"].string), url.scheme == "https" { Link(row["title"].string, destination: url) } } }
                }
            }
        }.navigationTitle("家庭 Lp(a) 对照").task { await store.refreshMembers() }
            .sheet(item: $relationship, onDismiss: { Task { await compare() } }) { row in NavigationStack { RelationshipEditor(pair: row.pair, options: row.options) } }
    }
    private func memberName(_ id: Int) -> String { store.members.first { $0.id == id }?.name ?? "成员" }
    @ViewBuilder private func recordSource(person: JSONValue, record: JSONValue) -> some View {
        let components = record["source_url"].string.split(separator: "/").map(String.init)
        if let index = components.firstIndex(of: "reports"), components.indices.contains(index + 1),
           let reportID = Int(components[index + 1]), let member = store.members.first(where: { $0.id == person["id"].int }) {
            NavigationLink("查看来源报告 #\(reportID)") { ReportDetailView(member: member, reportID: reportID) }.font(.caption)
        } else { Text("手动记录 #\(record["id"].int)").font(.caption).foregroundStyle(.secondary) }
    }
    private func compare() async {
        guard selected.count >= 2, !busy else { return }; busy = true; error = nil
        let token = store.generation; let requestSignature = signature; defer { busy = false }
        do {
            let data: JSONValue = try await store.requireAPI().request("/family/lpa/compare", method: "POST", body: ["member_ids": selected.sorted(), "record_choices": choices])
            guard store.isCurrent(token), requestSignature == signature else { return }; result = data; sourceSignature = requestSignature
        } catch { if store.isCurrent(token) { self.error = error.localizedDescription; result = nil } }
    }
}
struct RelationshipSelection: Identifiable { let id = UUID(); let pair: JSONValue; let options: JSONValue }
@MainActor
struct RelationshipEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let pair: JSONValue; let options: JSONValue
    @State private var kind = "unknown"
    @State private var confirmed = false
    @State private var busy = false
    @State private var error: String?
    private var keys: [String] { if case .object(let map) = options { return map.keys.sorted() }; return [] }
    var body: some View {
        Form {
            Picker("关系", selection: $kind) { ForEach(keys, id: \.self) { Text(options[$0].string).tag($0) } }
            Toggle("我已核实双方的关系，并确认保存。", isOn: $confirmed).font(.footnote)
            Text("修改需要双方档案的管理权限，系统会记录确认账号、时间和版本。").font(.caption).foregroundStyle(.secondary)
            InlineError(message: error)
            BusyButton(title: "确认保存关系", busy: busy) { Task { await save() } }.disabled(!confirmed)
        }.disabled(busy).navigationTitle("核实家人关系").navigationBarTitleDisplayMode(.inline).onAppear { kind = pair["kind"].string }
            .interactiveDismissDisabled(busy).toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) } }
    }
    private func save() async {
        busy = true; let token = store.generation; defer { busy = false }
        do { try await store.requireAPI().send("/family/relationships/\(pair["first_member_id"].int)/\(pair["second_member_id"].int)", method: "PUT", body: ["kind": kind, "confirmed": true, "revision": pair["revision"].int]); if store.isCurrent(token) { dismiss() } }
        catch { if store.isCurrent(token) { self.error = error.localizedDescription } }
    }
}
