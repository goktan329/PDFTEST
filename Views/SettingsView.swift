import SwiftUI
import SwiftData

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var llmService: LLMService
    @Query private var pdfSources: [PDFSourceModel]
    @Query private var questions: [QuestionModel]
    @Query private var sessions: [SolveSessionModel]
    @Query private var wrongQuestions: [WrongQuestionBankModel]
    @Query private var qualityQuestions: [QualityQuestionModel]
    
    @AppStorage("autoSaveDrawing") private var autoSaveDrawing = true
    @AppStorage("hapticFeedback") private var hapticFeedback = true
    @AppStorage("showTimer") private var showTimer = true
    @AppStorage("autoAdvanceOnAnswer") private var autoAdvanceOnAnswer = false
    @AppStorage("penColor") private var penColorHex = "#000000"
    @AppStorage("penWidth") private var penWidth = 3.0
    @AppStorage("preferredLanguage") private var preferredLanguage = "tr"
    @AppStorage("enableAISolutions") private var enableAISolutions = true
    
    @State private var showModelDownloader = false
    @State private var showExportSheet = false
    @State private var showResetConfirm = false
    @State private var showDeleteAllConfirm = false
    @State private var exportedFileURL: URL?
    
    private let penColors = ["#000000", "#FF3B30", "#007AFF", "#34C759", "#FF9F0A", "#AF52DE"]
    
    var body: some View {
        NavigationStack {
            List {
                // AI Model Bölümü
                Section {
                    AIModelStatusView()
                    
                    Button(action: { showModelDownloader = true }) {
                        Label("Model İndir / Yönet", systemImage: "arrow.down.circle")
                    }
                    .disabled(llmService.isModelLoaded)
                } header: {
                    Text("Yapay Zeka Modeli (Offline)")
                } footer: {
                    Text("AI çözümler için cihazınıza bir LLM modeli indirmeniz gerekir. İnternet bağlantısı olmadan çalışır. Model boyutu ~1-2 GB.")
                }
                
                // Çizim Ayarları
                Section {
                    Toggle("Otomatik Çizim Kaydet", isOn: $autoSaveDrawing)
                    Toggle("Dokunsal Geri Bildirim", isOn: $hapticFeedback)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Kalem Rengi")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(penColors, id: \.self) { color in
                                    Circle()
                                        .fill(Color(hex: color))
                                        .frame(width: 30, height: 30)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.primary, lineWidth: penColorHex == color ? 3 : 0)
                                        )
                                        .onTapGesture { penColorHex = color }
                                }
                            }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Kalem Kalınlığı: \(Int(penWidth)) pt")
                        Slider(value: $penWidth, in: 1...10, step: 0.5)
                    }
                } header: {
                    Text("Çizim Ayarları")
                }
                
                // Çözüm Ayarları
                Section {
                    Toggle("Süreyi Göster", isOn: $showTimer)
                    Toggle("Cevap Sonra Otomatik İlerle", isOn: $autoAdvanceOnAnswer)
                    Toggle("AI Çözümlerini Etkinleştir", isOn: $enableAISolutions)
                    
                    Picker("Dil", selection: $preferredLanguage) {
                        Text("Türkçe").tag("tr")
                        Text("English").tag("en")
                    }
                } header: {
                    Text("Çözüm Deneyimi")
                }
                
                // Veri Yönetimi
                Section {
                    Button(action: { showExportSheet = true }) {
                        Label("Verileri Dışa Aktar (JSON)", systemImage: "square.and.arrow.up")
                    }
                    
                    Button(action: { /* Import */ }) {
                        Label("Verileri İçe Aktar", systemImage: "square.and.arrow.down")
                    }
                    
                    NavigationLink("Yedekleme ve Geri Yükleme", destination: BackupView())
                } header: {
                    Text("Veri Yönetimi")
                }
                
                // İstatistikler
                Section {
                    StatRow(label: "PDF Kaynakları", value: "\(pdfSources.count)")
                    StatRow(label: "Toplam Soru", value: "\(questions.count)")
                    StatRow(label: "Çözüm Oturumları", value: "\(sessions.count)")
                    StatRow(label: "Yanlış/Boş Sorular", value: "\(wrongQuestions.count)")
                    StatRow(label: "Kaliteli Sorular", value: "\(qualityQuestions.count)")
                    
                    if let totalSize = calculateTotalSize() {
                        StatRow(label: "Depolama Kullanımı", value: formatBytes(totalSize))
                    }
                } header: {
                    Text("İstatistikler")
                }
                
                // Tehlikeli Bölge
                Section {
                    Button(role: .destructive) {
                        showResetConfirm = true
                    } label: {
                        Label("Tüm Çözüm Geçmişini Temizle", systemImage: "trash")
                    }
                    
                    Button(role: .destructive) {
                        showDeleteAllConfirm = true
                    } label: {
                        Label("TÜM VERİLERİ SİL (Geri Alınamaz)", systemImage: "trash.fill")
                    }
                } header: {
                    Text("Tehlikeli İşlemler")
                }
                
                // Hakkında
                Section {
                    HStack {
                        Text("Sürüm")
                        Spacer()
                        Text("1.0.0 (MVP)")
                            .foregroundStyle(.secondary)
                    }
                    
                    Link(destination: URL(string: "https://github.com/")!) {
                        HStack {
                            Text("Kaynak Kod / Lisans")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Text("Bu uygulama tamamen offline çalışır. Verileriniz cihazınızdan asla çıkmaz.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Hakkında")
                }
            }
            .navigationTitle("Ayarlar")
            .sheet(isPresented: $showModelDownloader) {
                ModelDownloaderView()
            }
            .sheet(isPresented: $showExportSheet) {
                ExportDataView()
            }
            .confirmationDialog("Çözüm geçmişi silinecek. Emin misiniz?", isPresented: $showResetConfirm) {
                Button("Evet, Temizle", role: .destructive) { clearSolveHistory() }
                Button("İptal", role: .cancel) { }
            }
            .confirmationDialog("TÜM VERİLER SİLİNECEK. Bu işlem geri alınamaz!", isPresented: $showDeleteAllConfirm) {
                Button("EVET, HERŞEYİ SİL", role: .destructive) { deleteAllData() }
                Button("İptal", role: .cancel) { }
            }
        }
    }
    
    private func calculateTotalSize() -> Int64? {
        let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let pdfDir = docsURL.appendingPathComponent("PDFImports")
        
        guard let enumerator = FileManager.default.enumerator(at: pdfDir, includingPropertiesForKeys: [.fileSizeKey]) else { return nil }
        
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func clearSolveHistory() {
        for session in sessions {
            modelContext.delete(session)
        }
        for attempt in sessions.flatMap({ $0.attempts }) {
            modelContext.delete(attempt)
        }
        try? modelContext.save()
    }
    
    private func deleteAllData() {
        // Tüm entity'leri sil
        let entities: [any PersistentModel.Type] = [
            SolveSessionModel.self,
            UserAttemptModel.self,
            WrongQuestionBankModel.self,
            QualityQuestionModel.self,
            QuestionModel.self,
            OptionModel.self,
            PDFSourceModel.self,
            LearningOutcomeModel.self,
            TopicModel.self,
            SubjectModel.self
        ]
        
        for entity in entities {
            let descriptor = FetchDescriptor<AnyPersistentModel>()
            // SwiftData'da toplu silme için her entity için ayrı fetch + delete
        }
        try? modelContext.save()
        
        // PDF dosyalarını da sil
        let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let pdfDir = docsURL.appendingPathComponent("PDFImports")
        try? FileManager.default.removeItem(at: pdfDir)
    }
}

// MARK: - AI Model Status View

struct AIModelStatusView: View {
    @EnvironmentObject var llmService: LLMService
    
    var body: some View {
        HStack(spacing: 16) {
            // Durum göstergesi
            ZStack {
                Circle()
                    .fill(llmService.isModelLoaded ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                    .frame(width: 50, height: 50)
                Image(systemName: llmService.isModelLoaded ? "brain.head.profile" : "brain")
                    .font(.title2)
                    .foregroundStyle(llmService.isModelLoaded ? .green : .orange)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(llmService.isModelLoaded ? "Model Yüklü" : "Model Yüklenmedi")
                    .font(.headline)
                Text(llmService.currentStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if llmService.isModelLoaded {
                Button("Kaldır") {
                    llmService.unloadModel()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button("Yükle") {
                    Task {
                        try? await llmService.loadModel()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Model Downloader View

struct ModelDownloaderView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var llmService: LLMService
    
    @State private var selectedModelIndex = 0
    @State private var downloadProgress: Double = 0
    @State private var downloadStatus = "Hazır"
    @State private var isDownloading = false
    
    private let models = ModelInfo.recommendedModels
    
    var body: some View {
        NavigationStack {
            List {
                Section("Önerilen Modeller") {
                    ForEach(Array(models.enumerated()), id: \.offset) { index, model in
                        ModelOptionRow(
                            model: model,
                            isSelected: selectedModelIndex == index,
                            isDownloaded: isModelDownloaded(model.name)
                        ) {
                            selectedModelIndex = index
                        }
                    }
                }
                
                Section("İndirme") {
                    if isDownloading {
                        VStack(spacing: 12) {
                            ProgressView(value: downloadProgress)
                            Text(downloadStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("İptal") { cancelDownload() }
                                .buttonStyle(.bordered)
                        }
                    } else {
                        Button(action: startDownload) {
                            Label("Seçili Modeli İndir", systemImage: "arrow.down.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedModelIndex < 0)
                    }
                    
                    if let downloadedPath = getDownloadedModelPath() {
                        Text("İndirilen: \(downloadedPath.lastPathComponent)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section("Bilgi") {
                    Text("Modeller Hugging Face'den indirilir. İlk indirme internet gerektirir, sonrasında tamamen offline çalışır.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    
                    ForEach(models[selectedModelIndex].description.components(separatedBy: ", "), id: \.self) { feature in
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(feature)
                        }
                    }
                }
            }
            .navigationTitle("Model Yöneticisi")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }
    
    private func isModelDownloaded(_ name: String) -> Bool {
        let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let path = docsURL.appendingPathComponent(name).path
        return FileManager.default.fileExists(atPath: path)
    }
    
    private func getDownloadedModelPath() -> URL? {
        let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let modelName = models[selectedModelIndex].name
        let path = docsURL.appendingPathComponent(modelName)
        return FileManager.default.fileExists(atPath: path.path) ? path : nil
    }
    
    private func startDownload() {
        let model = models[selectedModelIndex]
        isDownloading = true
        downloadProgress = 0
        downloadStatus = "İndiriliyor: \(model.name)..."
        
        // Gerçek implementasyonda URLSession download task
        // Bu örnekte simülasyon
        Task {
            for i in 1...20 {
                try await Task.sleep(nanoseconds: 300_000_000)
                await MainActor.run {
                    downloadProgress = Double(i) / 20.0
                    downloadStatus = "İndiriliyor: %\(Int(downloadProgress * 100))"
                }
            }
            await MainActor.run {
                isDownloading = false
                downloadStatus = "İndirildi! Modeli yüklemek için 'Yükle' butonuna basın."
            }
        }
    }
    
    private func cancelDownload() {
        isDownloading = false
        downloadStatus = "İptal edildi"
    }
}

struct ModelOptionRow: View {
    let model: (name: String, size: String, description: String, url: String)
    let isSelected: Bool
    let isDownloaded: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Seçim göstergesi
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.accentColor : Color.secondary, lineWidth: 2)
                        .frame(width: 24, height: 24)
                    if isSelected {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 12, height: 12)
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(model.name)
                            .font(.subheadline)
                            .lineLimit(1)
                        if isDownloaded {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        }
                    }
                    Text("\(model.size) • \(model.description)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Export Data View

struct ExportDataView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var questions: [QuestionModel]
    @Query private var sessions: [SolveSessionModel]
    @Query private var subjects: [SubjectModel]
    @Query private var topics: [TopicModel]
    @Query private var outcomes: [LearningOutcomeModel]
    
    @State private var includeQuestions = true
    @State private var includeSessions = true
    @State private var includeSubjects = true
    @State private var isExporting = false
    @State private var exportURL: URL?
    @State private var showShareSheet = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Dahil Edilecek Veriler") {
                    Toggle("Sorular", isOn: $includeQuestions)
                    Toggle("Çözüm Oturumları", isOn: $includeSessions)
                    Toggle("Ders/Konu/Kazanım Yapısı", isOn: $includeSubjects)
                }
                
                Section {
                    Button(action: exportData) {
                        if isExporting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Label("JSON Olarak Dışa Aktar", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isExporting)
                }
                
                if let url = exportURL {
                    Section("Sonuç") {
                        Text("Dosya hazır: \(url.lastPathComponent)")
                            .font(.caption)
                        Button("Paylaş / Kaydet") {
                            showShareSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Verileri Dışa Aktar")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = exportURL {
                    ShareSheet(activityItems: [url])
                }
            }
        }
    }
    
    private func exportData() {
        isExporting = true
        
        Task.detached {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            
            var exportData: [String: Any] = [:]
            exportData["exportDate"] = ISO8601DateFormatter().string(from: Date())
            exportData["version"] = "1.0"
            
            if includeSubjects {
                // Subject/Topic/Outcome export
            }
            
            if includeQuestions {
                // Question export
            }
            
            if includeSessions {
                // Session export
            }
            
            // Dosyaya yaz
            let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fileName = "OfflineTestApp_Export_\(Date().timeIntervalSince1970).json"
            let url = docsURL.appendingPathComponent(fileName)
            
            // JSON serialization burada yapılacak
            // "{}".data(using: .utf8)!.write(to: url)
            
            await MainActor.run {
                self.exportURL = url
                self.isExporting = false
            }
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Backup View (Placeholder)

struct BackupView: View {
    var body: some View {
        List {
            Section("iCloud Yedekleme") {
                Toggle("Otomatik iCloud Yedekleme", isOn: .constant(false))
                Text("SwiftData iCloud sync henüz bu sürümde aktif değil.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section("Manuel Yedek") {
                Button("Yedek Al") { }
                Button("Yedekten Geri Yükle") { }
            }
        }
        .navigationTitle("Yedekleme")
    }
}

// MARK: - Stat Row

struct StatRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}