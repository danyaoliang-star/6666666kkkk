import SwiftUI

@MainActor
struct ChatView: View {
    @EnvironmentObject var store: AppStore
    let member: Member
    var reportID: Int? = nil
    @State private var conversations: [Conversation] = []
    @State private var conversationID: Int?
    @State private var messages: [ChatMessage] = []
    @State private var text = ""
    @State private var busy = false
    @State private var error: String?
    @State private var choosing = false
    @State private var service: JSONValue?
    @State private var memorySource: ChatMessage?
    var body: some View {
        VStack(spacing: 0) {
            if !member.allows("read") { EmptyNotice(title: "尚未获得档案查看权限", detail: "可以前往计划页查看获授权的监督信息。", symbol: "lock.shield") }
            else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            if messages.isEmpty {
                                VStack(alignment: .leading, spacing: 18) {
                                    Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(AppTheme.accent)
                                    Text("今天，想了解\n什么健康近况？").font(.largeTitle.bold())
                                    Text("一起看看\(member.name)的健康记录和日常计划。").font(.subheadline).foregroundStyle(.secondary)
                                    ForEach(["最近的健康指标怎么样？", "今天的计划完成了吗？", "怎样整理检查报告？"], id: \.self) { question in
                                        Button { text = question } label: { HStack { Text(question); Spacer(); Image(systemName: "arrow.up.left") }.padding(16).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 18)) }.buttonStyle(.plain)
                                    }
                                }.padding(.vertical, 25)
                            }
                            ForEach(messages) { message in
                                HStack(alignment: .top) {
                                    if message.role == "user" { Spacer(minLength: 35) }
                                    VStack(alignment: .leading, spacing: 10) {
                                        if message.role != "user" { Label("小康", systemImage: "sparkles").font(.caption).foregroundStyle(AppTheme.accent) }
                                        Text(message.content).font(.body).lineSpacing(6).textSelection(.enabled)
                                        ForEach(message.attachments) { attachment in NavigationLink { ReportDetailView(member: member, reportID: attachment.reportId) } label: { Label(attachment.name, systemImage: "doc.richtext").font(.footnote) } }
                                        if let proposal = message.memoryProposal, !proposal["saved"].bool, !proposal["too_long"].bool, member.allows("write") {
                                            Button("核对并保存到健康记忆") { memorySource = message }.font(.footnote)
                                        }
                                    }.padding(17).background(message.role == "user" ? AppTheme.accent.opacity(0.12) : .white.opacity(0.85), in: RoundedRectangle(cornerRadius: 20))
                                    if message.role != "user" { Spacer(minLength: 15) }
                                }.id(message.id)
                            }
                            if busy { ProgressView("小康正在整理…").padding() }
                            InlineError(message: error)
                        }.padding(20)
                    }.scrollDismissesKeyboard(.interactively)
                        .onChange(of: messages.count) { _ in if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } } }
                }
            }
        }.appBackground()
            .safeAreaInset(edge: .bottom) {
                if member.allows("read") {
                    VStack(spacing: 7) {
                        if let reportID = reportID { Text("当前报告 #\(reportID)，发送问题后将用于报告解读。").font(.caption2).foregroundStyle(.secondary) }
                        HStack(alignment: .bottom, spacing: 12) {
                            TextField("向小康提问", text: $text, axis: .vertical).lineLimit(1...5).padding(12).background(.white, in: RoundedRectangle(cornerRadius: 18))
                            Button { Task { await send() } } label: { Image(systemName: "arrow.up").fontWeight(.bold).foregroundStyle(.white).padding(13).background(AppTheme.accent, in: Circle()) }.disabled(busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityLabel("发送")
                        }
                        Text(service?["configured"].bool == true ? "AI 回复仅供记录参考，请核对来源。" : "当前使用已保存档案进行问答。 ").font(.caption2).foregroundStyle(.secondary)
                    }.padding(.horizontal, 18).padding(.vertical, 10).background(.ultraThinMaterial)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button { choosing = true } label: { Image(systemName: "list.bullet") }.disabled(busy).accessibilityLabel("对话列表") }
                ToolbarItem(placement: .navigationBarTrailing) { Button { conversationID = nil; messages = []; error = nil } label: { Image(systemName: "square.and.pencil") }.disabled(busy).accessibilityLabel("新对话") }
            }
            .task { await initialize() }
            .sheet(isPresented: $choosing) {
                NavigationStack { List(conversations) { row in Button(row.title) { choosing = false; conversationID = row.id; messages = []; Task { await loadMessages() } } }.navigationTitle("历史对话").toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { choosing = false } } } }
            }
            .sheet(item: $memorySource) { source in NavigationStack { MemoryEditor(member: member, existing: nil, proposed: source.memoryProposal, sourceID: source.id) } }
    }
    private func initialize() async {
        guard member.allows("read") else { return }; let context = store.generation
        do {
            let api = try store.requireAPI()
            let list: [Conversation] = try await api.request("/members/\(member.id)/assistant/conversations")
            let status: JSONValue = try await api.request("/assistant/status")
            guard store.isCurrent(context), !Task.isCancelled else { return }; conversations = list; service = status
            if reportID == nil { conversationID = list.first?.id; await loadMessages() }
        } catch { if store.isCurrent(context), !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func loadMessages() async {
        guard let id = conversationID else { messages = []; return }; let context = store.generation
        do { let result: [ChatMessage] = try await store.requireAPI().request("/members/\(member.id)/assistant/messages?conversation_id=\(id)"); guard store.isCurrent(context), conversationID == id, !Task.isCancelled else { return }; messages = result }
        catch { if store.isCurrent(context), conversationID == id, !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func send() async {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !question.isEmpty else { return }; busy = true; error = nil
        let context = store.generation; defer { busy = false }
        do {
            let api = try store.requireAPI()
            if conversationID == nil {
                let row: Conversation = try await api.request("/members/\(member.id)/assistant/conversations", method: "POST", body: ["title": String(question.prefix(40))])
                guard store.isCurrent(context) else { return }; conversationID = row.id; conversations.insert(row, at: 0)
            }
            let id = conversationID!
            var body: [String: Any] = ["content": question, "conversation_id": id]
            if let reportID = reportID { body["report_id"] = reportID }
            let reply: ChatReply = try await api.request("/members/\(member.id)/assistant/messages", method: "POST", body: body)
            guard store.isCurrent(context), conversationID == id else { return }
            messages += reply.messages; text = ""
        } catch { if store.isCurrent(context) { self.error = error.localizedDescription } }
    }
}
