import SwiftUI

enum AppTheme {
    static let accent = Color(red: 0.40, green: 0.34, blue: 0.83)
    static let ink = Color(red: 0.13, green: 0.10, blue: 0.28)
    static let background = Color(red: 0.94, green: 0.94, blue: 0.985)
}
struct HealthCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.9)))
    }
}
struct EmptyNotice: View {
    let title: String
    var detail = ""
    var symbol = "tray"
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(AppTheme.accent.opacity(0.6))
            Text(title).font(.headline)
            if !detail.isEmpty { Text(detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center) }
        }.frame(maxWidth: .infinity).padding(24)
    }
}
struct InlineError: View {
    let message: String?
    var body: some View { if let message = message { Label(message, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(.red).padding(.vertical, 8).accessibilityAddTraits(.updatesFrequently) } }
}
struct BusyButton: View {
    let title: String; let busy: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) { HStack { if busy { ProgressView().tint(.white) }; Text(title).fontWeight(.semibold) }.frame(maxWidth: .infinity).padding(.vertical, 7) }
            .buttonStyle(.borderedProminent).disabled(busy)
    }
}
extension View {
    func appBackground() -> some View { self.background(AppTheme.background.ignoresSafeArea()) }
}
extension HealthScope {
    var color: Color {
        switch self {
        case .steps: return .orange
        case .activeEnergy: return .pink
        case .exerciseTime: return .teal
        case .sleep: return .purple
        case .heartRate: return .red
        case .bodyMass: return .blue
        }
    }
}
@MainActor
struct MemberPicker: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(store.members) { member in
                    Button { store.select(member) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: member.relation == "本人" ? "person.crop.circle.fill" : "person.crop.circle")
                            Text(member.name).fontWeight(.medium)
                        }.padding(.horizontal, 15).padding(.vertical, 10)
                            .foregroundStyle(store.selectedID == member.id ? .white : AppTheme.ink)
                            .background(store.selectedID == member.id ? AppTheme.accent : .white.opacity(0.85), in: Capsule())
                    }.accessibilityLabel("切换到" + member.name).accessibilityAddTraits(store.selectedID == member.id ? .isSelected : [])
                }
            }.padding(.horizontal, 20)
        }.padding(.vertical, 10)
    }
}
