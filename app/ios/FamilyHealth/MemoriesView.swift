import SwiftUI

@MainActor
struct MemoriesView: View {
    @EnvironmentObject var store: AppStore
    let member: Member
    @State private var items: [JSONValue] = []
    @State private var filter = "active"
    @State private var search = ""
    @State private var editor = false
    @State private var existing: JSONValue?
    @State private var canWrite = false
    @State private var error: String?
    var body: some View {
        List {
            Picker("状态", selection: $filter) { Text("生效").tag("active"); Text("停用").tag("archived"); Text("回收站").tag("deleted") }.pickerStyle(.segmented)
            Text("以下为用户确认保存的信息，不等同于已核实的诊断或处方。模型使用许可逐条设置。").font(.caption).foregroundStyle(.secondary)
            InlineError(message: error)
            ForEach(Array(items.filter { $0["state"].string == filter && (search.isEmpty || $0["content"].string.localizedCaseInsensitiveContains(search)) }.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 9) {
                    Text(row["content"].string)
                    Text(row["category"].string + (row["expired"].bool ? " · 已过期" : "") + (row["use_in_model"].bool ? " · 已允许指定模型使用" : " · 仅档案使用")).font(.caption2).foregroundStyle(.secondary)
                    if canWrite { Button(filter == "deleted" ? "查看并恢复" : "编辑") { existing = row; editor = true }.font(.caption) }
                }.padding(.vertical, 7)
            }
            if items.isEmpty { EmptyNotice(title: "还没有健康记忆", detail: "可记录过敏、用药情况、既往情况或生活偏好。", symbol: "brain.head.profile") }
        }.navigationTitle("健康记忆").searchable(text: $search, prompt: "搜索记忆")
            .toolbar { if canWrite { Button { existing = nil; editor = true } label: { Image(systemName: "plus") }.accessibilityLabel("添加健康记忆") } }
            .task { await load() }.refreshable { await load() }
            .sheet(isPresented: $editor, onDismiss: { Task { await load() } }) { NavigationStack { MemoryEditor(member: member, existing: existing) } }
    }
    private func load() async {
        let context = store.generation
        do { let result: JSONValue = try await store.requireAPI().request("/members/\(member.id)/memories"); guard store.isCurrent(context), !Task.isCancelled else { return }; items = result["items"].array; canWrite = result["can_write"].bool; error = nil }
        catch { if store.isCurrent(context), !Task.isCancelled { self.error = error.localizedDescription; items = []; canWrite = false } }
    }
}

@MainActor
struct MemoryEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let member: Member; let existing: JSONValue?
    var proposed: JSONValue? = nil
    var sourceID: Int? = nil
    @State private var content = ""
    @State private var category = "other"
    @State private var state = "active"
    @State private var hasExpiry = false
    @State private var expiry = Date()
    @State private var useModel = false
    @State private var confirmed = false
    @State private var service: JSONValue?
    @State private var busy = false
    @State private var error: String?
    private let categories = ["allergy": "过敏与不耐受", "medication": "用药情况", "history": "既往情况", "family_history": "家族情况", "preference": "生活偏好", "other": "其他信息"]
    var body: some View {
        Form {
            Section("\(member.name)的用户陈述") {
                Picker("分类", selection: $category) { ForEach(categories.keys.sorted(), id: \.self) { Text(categories[$0]!).tag($0) } }
                TextField("要记住的信息，最多 500 字", text: $content, axis: .vertical).lineLimit(4...10)
                Picker("状态", selection: $state) { Text("生效").tag("active"); Text("停用").tag("archived"); if existing != nil { Text("移入回收站").tag("deleted") } }
                Toggle("设置有效期", isOn: $hasExpiry)
                if hasExpiry { DatePicker("有效期至", selection: $expiry, displayedComponents: .date) }
            }
            Section("模型使用许可") {
                if service?["configured"].bool == true {
                    Text("当前模型服务：" + (service?["memory_destination"].string ?? "")).font(.caption)
                    Toggle("允许在小康普通问答中将此条发送给上述模型服务", isOn: $useModel).font(.footnote)
                } else { Text("当前未配置模型服务，此条仅保存在健康档案中。").font(.footnote).foregroundStyle(.secondary) }
                Text("停用、过期或移入回收站后不再作为健康记忆使用。历史对话仍保留原内容。").font(.caption).foregroundStyle(.secondary)
            }
            Toggle("我已核对内容和归属，同意按上述范围保存。", isOn: $confirmed).font(.footnote)
            InlineError(message: error)
            BusyButton(title: "确认保存", busy: busy) { Task { await save() } }.disabled(!confirmed || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || content.count > 500)
        }.disabled(busy).navigationTitle("核对健康记忆").navigationBarTitleDisplayMode(.inline).interactiveDismissDisabled(busy)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) } }
            .task {
                if let row = existing { content = row["content"].string; category = row["category"].string; state = row["state"].string; hasExpiry = row["valid_until"] != .null; expiry = AppDates.date(row["valid_until"].string) }
                else if let row = proposed { content = row["content"].string; category = row["category"].string.isEmpty ? "other" : row["category"].string }
                let context = store.generation
                do { let result: JSONValue = try await store.requireAPI().request("/assistant/status"); guard store.isCurrent(context), !Task.isCancelled else { return }; service = result; useModel = existing?["use_in_model"].bool == true && existing?["model_destination"].string == result["memory_destination"].string }
                catch { if store.isCurrent(context), !Task.isCancelled { self.error = error.localizedDescription } }
            }
    }
    private func save() async {
        busy = true; error = nil; let context = store.generation; defer { busy = false }
        do {
            var body: [String: Any] = ["category": category, "content": content, "state": state, "confirmed": true,
                "valid_until": hasExpiry ? AppDates.day(expiry) as Any : NSNull(), "use_in_model": useModel && state == "active",
                "model_destination": service?["memory_destination"].string ?? "", "revision": existing?["revision"].int ?? 0]
            if let sourceID = sourceID { body["source_message_id"] = sourceID }
            let suffix = existing.map { "/\($0["id"].int)" } ?? ""
            try await store.requireAPI().send("/members/\(member.id)/memories" + suffix, method: existing == nil ? "POST" : "PUT", body: body)
            if store.isCurrent(context) { dismiss() }
        } catch { if store.isCurrent(context) { self.error = error.localizedDescription } }
    }
}
