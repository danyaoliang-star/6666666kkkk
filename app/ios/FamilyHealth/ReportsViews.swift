import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import PDFKit
import AVFoundation

@MainActor
struct ReportsView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    let member: Member
    @State private var reports: [MedicalReport] = []
    @State private var trash = false
    @State private var query = ""
    @State private var importing = false
    @State private var photo: PhotosPickerItem?
    @State private var camera = false
    @State private var busy = false
    @State private var loading = true
    @State private var error: String?
    @State private var deleting: MedicalReport?
    var body: some View {
        List {
            if member.allows("write"), !trash {
                Section("添加就医资料") {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) { Button { Task { await openCamera() } } label: { Label("拍摄报告", systemImage: "camera") }.disabled(busy) }
                    PhotosPicker(selection: $photo, matching: .images) { Label("从照片选择报告", systemImage: "photo") }.disabled(busy)
                    Button { importing = true } label: { Label("从文件选择 PDF 或图片", systemImage: "doc.badge.plus") }.disabled(busy)
                    Text("每份最多 10 MB。照片会转为 JPG 后上传，原件由当前家和服务器保存并识别。").font(.caption).foregroundStyle(.secondary)
                }
            }
            InlineError(message: error)
            if busy { ProgressView("正在处理报告") }
            if loading { ProgressView("正在读取病历夹") }
            Section(trash ? "回收站" : "按报告日期整理") {
                ForEach(reports.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.name.localizedCaseInsensitiveContains(query) }) { report in
                    if trash {
                        VStack(alignment: .leading, spacing: 8) { reportLabel(report); if member.allows("write") { Button("恢复到病历夹") { Task { await restore(report) } }.disabled(busy) } }
                    } else {
                        NavigationLink { ReportDetailView(member: member, reportID: report.id) } label: { reportLabel(report) }
                            .swipeActions { if member.allows("write") { Button(role: .destructive) { deleting = report } label: { Label("移入回收站", systemImage: "trash") } } }
                    }
                }
                if reports.isEmpty && !loading { EmptyNotice(title: trash ? "回收站为空" : "还没有就医资料", detail: trash ? "" : "上传报告后，可以识别日期、核对指标并查看原件。", symbol: "folder") }
            }
        }.navigationTitle(trash ? "报告回收站" : "病历夹").searchable(text: $query, prompt: "搜索检测名称或文件名")
            .toolbar { Button(trash ? "病历夹" : "回收站") { trash.toggle(); Task { await load() } }.disabled(busy) }
            .task {
                await load()
                while !Task.isCancelled {
                    do { try await Task.sleep(nanoseconds: 3_000_000_000) } catch { return }
                    if scenePhase == .active && reports.contains(where: \.pending) && !busy { await load(background: true) }
                }
            }.refreshable { await load() }
            .onChange(of: photo) { item in if let item = item { Task { await importPhoto(item) } } }
            .sheet(isPresented: $camera) { NativeCamera { image in camera = false; if let image = image { Task { await importCamera(image) } } }.ignoresSafeArea() }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .jpeg, .png]) { result in
                switch result { case .success(let url): Task { await importFile(url) }; case .failure(let cause): error = cause.localizedDescription }
            }
            .confirmationDialog("将报告移入回收站？已入档指标和来源记录会保留，报告可以恢复。", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("移入回收站", role: .destructive) { if let report = deleting { Task { await remove(report) } }; deleting = nil }
            }
    }
    private func reportLabel(_ report: MedicalReport) -> some View {
        HStack(spacing: 12) {
            Image(systemName: report.mime == "application/pdf" ? "doc.richtext" : "photo").font(.title2).foregroundStyle(AppTheme.accent)
            VStack(alignment: .leading, spacing: 7) {
                Text(report.title).font(.headline).lineLimit(2)
                Text(report.reportDate ?? "报告日期待确认").font(.caption).foregroundStyle(.secondary)
                Text(report.pending ? "正在识别，请稍候" : report.ocrStatus == "failed" ? "识别未完成，可重试或手动校对" : "已归档").font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 6)
    }
    private func load(background: Bool = false) async {
        let context = store.generation; let requestedTrash = trash
        do {
            let result: [MedicalReport] = try await store.requireAPI().request("/members/\(member.id)/reports?trash=\(requestedTrash)")
            guard store.isCurrent(context), !Task.isCancelled, trash == requestedTrash else { return }; reports = result; if !background { error = nil }
        } catch { if store.isCurrent(context), !Task.isCancelled { self.error = error.localizedDescription } }
        if store.isCurrent(context) { loading = false }
    }
    private func importPhoto(_ item: PhotosPickerItem) async {
        guard !busy else { return }; busy = true; error = nil; let context = store.generation; defer { busy = false; photo = nil }
        do {
            guard let bytes = try await item.loadTransferable(type: Data.self), let image = UIImage(data: bytes), let jpeg = image.jpegData(compressionQuality: 0.9) else { throw ClientError.server(422, "无法读取这张照片，请换一张重试。") }
            guard store.isCurrent(context) else { return }
            let _: MedicalReport = try await store.requireAPI().upload(memberID: member.id, data: jpeg, filename: "报告-\(UUID().uuidString).jpg", mime: "image/jpeg")
            if store.isCurrent(context) { await load() }
        } catch { if store.isCurrent(context) { self.error = error.localizedDescription } }
    }
    private func openCamera() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        let context = store.generation
        let allowed = await AVCaptureDevice.requestAccess(for: .video)
        guard store.isCurrent(context) else { return }
        if allowed { camera = true } else { error = "请在 iPhone「设置 → 家和」中允许使用相机，也可以从照片或文件选择报告。" }
    }
    private func importCamera(_ image: UIImage) async {
        guard !busy else { return }; busy = true; error = nil; let context = store.generation; defer { busy = false }
        do {
            guard let bytes = image.jpegData(compressionQuality: 0.9) else { throw ClientError.server(422, "无法读取拍摄的照片，请重试。") }
            let _: MedicalReport = try await store.requireAPI().upload(memberID: member.id, data: bytes, filename: "拍摄报告-\(UUID().uuidString).jpg", mime: "image/jpeg")
            if store.isCurrent(context) { await load() }
        } catch { if store.isCurrent(context) { self.error = error.localizedDescription } }
    }
    private func importFile(_ url: URL) async {
        guard !busy else { return }; busy = true; error = nil; let context = store.generation; defer { busy = false }
        let securityScope = url.startAccessingSecurityScopedResource(); defer { if securityScope { url.stopAccessingSecurityScopedResource() } }
        do {
            if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 10 * 1024 * 1024 { throw ClientError.oversizedFile }
            let bytes = try Data(contentsOf: url, options: .mappedIfSafe)
            let mime = url.pathExtension.lowercased() == "pdf" ? "application/pdf" : url.pathExtension.lowercased() == "png" ? "image/png" : "image/jpeg"
            let _: MedicalReport = try await store.requireAPI().upload(memberID: member.id, data: bytes, filename: url.lastPathComponent, mime: mime)
            if store.isCurrent(context) { await load() }
        } catch { if store.isCurrent(context) { self.error = error.localizedDescription } }
    }
    private func remove(_ report: MedicalReport) async {
        busy = true; let context = store.generation; defer { busy = false }
        do { try await store.requireAPI().send("/members/\(member.id)/reports/\(report.id)", method: "DELETE"); if store.isCurrent(context) { await load() } }
        catch { if store.isCurrent(context) { self.error = error.localizedDescription } }
    }
    private func restore(_ report: MedicalReport) async {
        busy = true; let context = store.generation; defer { busy = false }
        do { try await store.requireAPI().send("/members/\(member.id)/reports/\(report.id)/restore", method: "POST"); if store.isCurrent(context) { await load() } }
        catch { if store.isCurrent(context) { self.error = error.localizedDescription } }
    }
}

struct NativeCamera: UIViewControllerRepresentable {
    let completion: (UIImage?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController(); picker.sourceType = .camera; picker.mediaTypes = [UTType.image.identifier]; picker.delegate = context.coordinator; return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let completion: (UIImage?) -> Void
        init(completion: @escaping (UIImage?) -> Void) { self.completion = completion }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) { completion(info[.originalImage] as? UIImage) }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { completion(nil) }
    }
}

@MainActor
struct ReportDetailView: View {
    @EnvironmentObject var store: AppStore
    let member: Member; let reportID: Int
    @State private var report: JSONValue?
    @State private var date = Date()
    @State private var name = ""
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        List {
            InlineError(message: error)
            if let report = report {
                Section("来源原件") {
                    Text(report["test_name"].string.isEmpty ? report["name"].string : report["test_name"].string).font(.headline)
                    Text("原文件：" + report["name"].string).font(.caption).foregroundStyle(.secondary)
                    NavigationLink("查看完整原件") { DocumentPreview(memberID: member.id, reportID: reportID, title: report["name"].string, mime: report["mime"].string) }
                    Text("识别状态：" + report["ocr_status"].string).font(.footnote)
                    if !report["ocr_error"].string.isEmpty { Text(report["ocr_error"].string).font(.footnote).foregroundStyle(.red) }
                    if member.allows("write") {
                        NavigationLink("校对指标并入档") { ReportReviewView(member: member, reportID: reportID) }
                        if report["ocr_status"].string == "failed" { Button("重新识别") { Task { await update("retry", method: "POST", body: nil) } }.disabled(busy) }
                    }
                    NavigationLink("让小康分析这份报告") { ChatView(member: member, reportID: reportID) }
                }
                if member.allows("write") {
                    Section("核对报告日期") {
                        DatePicker("报告日期", selection: $date, in: ...Date(), displayedComponents: .date)
                        Button("确认并保存日期") { Task { await update("date", method: "PATCH", body: ["report_date": AppDates.day(date), "revision": report["revision"].int]) } }.disabled(busy)
                        Text("日期修改会同步更新这份报告已确认入档的指标日期。").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("检测名称") { TextField("检测内容", text: $name); Button("保存名称") { Task { await update("test-name", method: "PATCH", body: ["test_name": name, "revision": report["revision"].int]) } }.disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty) }
                }
                Section("识别原文") { Text(report["ocr_text"].string.isEmpty ? "暂无识别文字。" : report["ocr_text"].string).font(.footnote).textSelection(.enabled) }
            } else { ProgressView("读取报告") }
        }.navigationTitle("报告详情").task { await load() }.refreshable { await load() }
    }
    private func load() async {
        let context = store.generation
        do { let result: JSONValue = try await store.requireAPI().request("/members/\(member.id)/reports/\(reportID)"); guard store.isCurrent(context), !Task.isCancelled else { return }; report = result; date = AppDates.date(result["report_date"].string); name = result["test_name"].string }
        catch { if store.isCurrent(context), !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func update(_ suffix: String, method: String, body: [String: Any]?) async {
        busy = true; error = nil; let context = store.generation; defer { busy = false }
        do { try await store.requireAPI().send("/members/\(member.id)/reports/\(reportID)/" + suffix, method: method, body: body); if store.isCurrent(context) { await load() } }
        catch { if store.isCurrent(context) { self.error = error.localizedDescription } }
    }
}

struct NativePDF: UIViewRepresentable {
    let data: Data
    func makeUIView(context: Context) -> PDFView { let view = PDFView(); view.autoScales = true; view.document = PDFDocument(data: data); return view }
    func updateUIView(_ view: PDFView, context: Context) {}
}
@MainActor
struct DocumentPreview: View {
    @EnvironmentObject var store: AppStore
    let memberID: Int; let reportID: Int; let title: String; let mime: String
    @State private var data: Data?
    @State private var error: String?
    var body: some View {
        Group {
            if let data = data {
                if data.starts(with: Data("%PDF".utf8)) { NativePDF(data: data) }
                else if let image = UIImage(data: data) { ScrollView([.horizontal, .vertical]) { Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: 1200) } }
                else { EmptyNotice(title: "无法显示原件", detail: "文件格式可能已损坏。") }
            } else if let error = error { EmptyNotice(title: "原件读取失败", detail: error) }
            else { ProgressView("读取原件") }
        }.navigationTitle(title).navigationBarTitleDisplayMode(.inline).privacySensitive()
            .task {
                let context = store.generation
                do { let result = try await store.requireAPI().bytes("/members/\(memberID)/reports/\(reportID)/file"); guard store.isCurrent(context), !Task.isCancelled else { return }; data = result }
                catch { if store.isCurrent(context), !Task.isCancelled { self.error = error.localizedDescription } }
            }.onDisappear { data = nil }
    }
}

struct ReviewRow: Identifiable {
    let id = UUID()
    var selected: Bool; var code: String; var value: String; var unit: String
    var condition: String; var low: String; var high: String
    let sourceIndex: Int?; let original: String; let existing: Bool
}
@MainActor
struct ReportReviewView: View {
    @EnvironmentObject var store: AppStore
    let member: Member; let reportID: Int
    @State private var result: JSONValue?
    @State private var rows: [ReviewRow] = []
    @State private var date = Date()
    @State private var acknowledged = false
    @State private var busy = false
    @State private var error: String?
    private var confirmed: Bool { result?["confirmation"] != nil && result?["confirmation"] != .null }
    var body: some View {
        Form {
            InlineError(message: error)
            if let result = result {
                if confirmed {
                    Section("已确认入档") { ForEach(Array(result["confirmation"]["records"].array.enumerated()), id: \.offset) { _, row in Text("\(store.catalog[row["code"].string]?.name ?? row["code"].string)：\(row["value"].string) · \(row["measured_at"].string)") }; Text("已确认值不会被后续识别覆盖。").font(.caption).foregroundStyle(.secondary) }
                } else if result["ocr_status"].string != "done" { Text("请等待识别完成。识别失败时可在详情页重试，或从健康记录手动录入。").font(.footnote) }
                else {
                    Section("对照原件") { NavigationLink("查看报告原件") { DocumentPreview(memberID: member.id, reportID: reportID, title: "报告原件", mime: "application/pdf") }; DatePicker("报告日期", selection: $date, in: ...Date(), displayedComponents: .date) }
                    ForEach($rows) { $row in
                        Section {
                            Toggle(row.existing ? "已录入此项目" : "本次入档", isOn: $row.selected).disabled(row.existing)
                            Text(row.original).font(.caption).foregroundStyle(.secondary)
                            Picker("指标", selection: $row.code) { Text("请选择").tag(""); ForEach(store.catalog.keys.sorted(), id: \.self) { Text(store.catalog[$0]!.name).tag($0) } }
                            TextField("结果", text: $row.value).keyboardType(.decimalPad)
                            TextField("单位", text: $row.unit)
                            TextField("测量条件，不明确填“未注明”", text: $row.condition)
                            TextField("参考下限（选填）", text: $row.low).keyboardType(.decimalPad)
                            TextField("参考上限（选填）", text: $row.high).keyboardType(.decimalPad)
                        }.disabled(row.existing || busy)
                    }
                    Button("补充一项") { rows.append(ReviewRow(selected: true, code: "", value: "", unit: "", condition: "未注明", low: "", high: "", sourceIndex: nil, original: "人工补充", existing: false)) }.disabled(busy)
                    Toggle("我已核对成员、报告日期、所选指标和原件，确认保存。", isOn: $acknowledged).font(.footnote).disabled(busy)
                    BusyButton(title: "确认并批量入档", busy: busy) { Task { await save() } }.disabled(!acknowledged || !rows.contains { $0.selected })
                }
            } else { ProgressView("读取待校对内容") }
        }.navigationTitle("指标校对").task { await load() }
    }
    private func load() async {
        let context = store.generation
        do {
            let value: JSONValue = try await store.requireAPI().request("/members/\(member.id)/reports/\(reportID)/review")
            guard store.isCurrent(context), !Task.isCancelled else { return }; result = value; acknowledged = false
            date = AppDates.date(value["report_date"].string)
            let existing = Set(value["existing_records"].array.map { $0["code"].string })
            rows = value["candidates"].array.map { row in
                ReviewRow(selected: row["suggested"].bool && !existing.contains(row["code"].string), code: row["code"].string, value: row["value"].string, unit: row["unit"].string, condition: row["condition"].string.isEmpty ? "未注明" : row["condition"].string, low: row["ref_low"].string, high: row["ref_high"].string, sourceIndex: row["source_index"].optionalNumber.map(Int.init), original: row["name"].string + " " + row["value"].string + " " + row["unit"].string + " · " + row["reference"].string, existing: existing.contains(row["code"].string))
            }
        } catch { if store.isCurrent(context), !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func save() async {
        guard let result = result else { return }; busy = true; error = nil; let context = store.generation; defer { busy = false }
        do {
            var items: [[String: Any]] = []
            for row in rows where row.selected && !row.existing {
                guard let number = Double(row.value), number.isFinite, store.catalog[row.code]?.unit == row.unit,
                      !row.condition.trimmingCharacters(in: .whitespaces).isEmpty,
                      (row.low.isEmpty || Double(row.low) != nil), (row.high.isEmpty || Double(row.high) != nil) else { throw ClientError.server(422, "请核对所选项目、数值、单位、条件和参考范围；带 < 或 > 的结果暂不直接入档。") }
                items.append(["code": row.code, "value": number, "unit": row.unit, "condition": row.condition,
                              "ref_low": Double(row.low).map { $0 as Any } ?? NSNull(), "ref_high": Double(row.high).map { $0 as Any } ?? NSNull(), "source_index": row.sourceIndex.map { $0 as Any } ?? NSNull()])
            }
            try await store.requireAPI().send("/members/\(member.id)/reports/\(reportID)/confirm", method: "POST", body: ["revision": result["revision"].int, "report_date": AppDates.day(date), "confirmed": true, "items": items])
            if store.isCurrent(context) { await load() }
        } catch { if store.isCurrent(context) { self.error = error.localizedDescription } }
    }
}
