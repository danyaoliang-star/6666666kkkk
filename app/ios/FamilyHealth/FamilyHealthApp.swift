import SwiftUI

@main
@MainActor
struct FamilyHealthApp: App {
    @StateObject private var store = AppStore()
    var body: some Scene {
        WindowGroup {
            Group {
                if store.account == nil { LoginView() }
                else { MainTabs().id(store.account?.username) }
            }.environmentObject(store).tint(AppTheme.accent).preferredColorScheme(.light)
        }
    }
}

@MainActor
struct LoginView: View {
    @EnvironmentObject var store: AppStore
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var connectionSettings = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                Image(systemName: "heart.text.square.fill").font(.system(size: 58)).foregroundStyle(AppTheme.accent).padding(.top, 45)
                Text("家和").font(.largeTitle.bold()).foregroundStyle(AppTheme.ink)
                Text("把家人的健康，\n放在心上。").font(.system(size: 30, weight: .semibold)).lineSpacing(7)
                Text("保存每一份报告，记录每一天的变化。").foregroundStyle(.secondary)
                HealthCard {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("登录家庭健康档案").font(.title3.bold())
                        DisclosureGroup("服务器设置", isExpanded: $connectionSettings) {
                            VStack(alignment: .leading, spacing: 9) {
                                TextField("家和服务地址（https://…）", text: $server).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.URL)
                                Text("首次连接时填写部署者提供的服务地址，用于同步档案数据。").font(.caption).foregroundStyle(.secondary)
                            }.padding(.top, 8)
                        }
                        Divider()
                        TextField("账号", text: $username).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Divider()
                        SecureField("密码", text: $password).textContentType(.password)
                        InlineError(message: store.error)
                        BusyButton(title: "登录", busy: store.busy) {
                            Task { await store.login(server: server, username: username, password: password); password = "" }
                        }.disabled(server.isEmpty || username.isEmpty || password.isEmpty)
                    }
                }
                Text("健康数据仅在你主动同意后读取。服务地址由部署者提供，数据将保存到该服务。")
                    .font(.footnote).foregroundStyle(.secondary)
                #if DEBUG
                DisclosureGroup("本地开发说明") {
                    Text("电脑启动后端后，请填写电脑的局域网地址，例如 http://192.168.1.10:8000。手机上的 127.0.0.1 指向手机自身。演示账号 demo / Health2026!，请勿用于生产。")
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                }
                #endif
            }.padding(24)
        }.appBackground().onAppear { server = store.savedServer; connectionSettings = server.isEmpty }
    }
}

@MainActor
struct MainTabs: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: Int
    init(initialTab: Int = 0) { _selectedTab = State(initialValue: initialTab) }
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { memberContent { member in ChatView(member: member) }.navigationTitle("小康") }.id(store.generation)
                .tabItem { Label("小康", systemImage: "bubble.left.and.bubble.right") }
                .tag(0)
            NavigationStack { memberContent { member in HealthHomeView(member: member) }.navigationTitle("健康") }.id(store.generation)
                .tabItem { Label("健康", systemImage: "heart.fill") }
                .tag(1)
            NavigationStack { memberContent { member in PlansView(member: member) }.navigationTitle("计划") }.id(store.generation)
                .tabItem { Label("计划", systemImage: "calendar.badge.clock") }
                .tag(2)
            NavigationStack { AccountView().navigationTitle("我的") }.id(store.generation)
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
                .tag(3)
        }
        .alert("提示", isPresented: Binding(get: { store.error != nil && store.account != nil }, set: { if !$0 { store.error = nil } })) {
            Button("知道了") { store.error = nil }
        } message: { Text(store.error ?? "") }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { return }
                if scenePhase == .active { await store.refreshMembers() }
            }
        }
        .onChange(of: scenePhase) { phase in if phase == .active { Task { await store.refreshMembers() } } }
    }
    @ViewBuilder private func memberContent<Content: View>(@ViewBuilder content: (Member) -> Content) -> some View {
        VStack(spacing: 0) {
            MemberPicker()
            if let member = store.member { content(member).id(store.generation) }
            else { EmptyNotice(title: "先建立一份健康档案", detail: "在「我的 → 家庭成员」中添加自己或家人。") }
        }.appBackground()
    }
}
