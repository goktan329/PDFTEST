import SwiftUI
import UniformTypeIdentifiers
import PDFKit

// MARK: - PDF Import View

struct PDFImportView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var pdfParser: PDFParserService
    @Query(sort: \PDFSourceModel.importedAt, order: .reverse) private var pdfSources: [PDFSourceModel]
    
    @State private var showDocumentPicker = false
    @State private var showParsingDetail = false
    @State private var parsingResult: PDFParserService.ParsedPDFResult?
    @State private var selectedSubject: Subject? = nil
    @State private var selectedCategory: ExamCategory = .topicTest
    @State private var showSubjectPicker = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Üst bilgi kartı
                infoCard
                
                // PDF listesi
                if pdfSources.isEmpty {
                    emptyState
                } else {
                    pdfList
                }
            }
            .navigationTitle("PDF Yükle")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showDocumentPicker = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                }
            }
            .fileImporter(
                isPresented: $showDocumentPicker,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: true
            ) { result in
                handleFileSelection(result)
            }
            .sheet(isPresented: $showParsingDetail) {
                if let result = parsingResult {
                    ParsingResultView(result: result, onSave: saveParsedQuestions)
                }
            }
        }
    }
    
    private var infoCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 40))
                .foregroundStyle(.blue.gradient)
            
            Text("Test Kitabı / Deneme PDF Yükle")
                .font(.headline)
            
            Text("Uygulama PDF'i tarayacak, soruları ayıracak, cevap anahtarını bulacak ve soruları kazanımlarına göre sınıflandıracak. Tamamen cihazınızda, internet olmadan çalışır.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // İpuçları
            VStack(alignment: .leading, spacing: 6) {
                Label("En iyi sonuç için: Net soru numaraları (1., 2.) ve şık harfleri (A, B, C, D, E) olan PDF'ler", systemImage: "checkmark.circle")
                Label("Cevap anahtarı son sayfalarda 'CEVAP ANAHTARI' başlığıyla olmalı", systemImage: "checkmark.circle")
                Label("Karmaşık layout'larda manuel düzeltme gerekebilir", systemImage: "exclamationmark.triangle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
        }
        .padding(20)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding()
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
    }
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "tray.fill")
                .font(.system(size: 60))
                .foregroundStyle(.secondary.opacity(0.5))
            
            Text("Henüz PDF Yüklenmedi")
                .font(.title2.bold())
            
            Text("Başlamak için '+' butonuna basıp\ntest kitabı veya deneme PDF'inizi seçin")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: { showDocumentPicker = true }) {
                Label("PDF Seç ve Yükle", systemImage: "doc.badge.plus")
                    .frame(maxWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var pdfList: some View {
        List {
            ForEach(pdfSources) { source in
                PDFSourceRow(source: source)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            deletePDFSource(source)
                        } label: {
                            Label("Sil", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.insetGrouped)
    }
    
    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                importPDF(from: url)
            }
        case .failure(let error):
            print("Dosya seçme hatası: \(error)")
        }
    }
    
    private func importPDF(from url: URL) {
        // Security-scoped resource erişimi
        guard url.startAccessingSecurityScopedResource() else {
            print("Güvenlik kapsamlı erişim reddedildi")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        // Dosyayı app sandbox'ına kopyala
        let fileName = url.lastPathComponent
        let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destURL = docsURL.appendingPathComponent("PDFImports").appendingPathComponent(fileName)
        
        try? FileManager.default.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        
        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: url, to: destURL)
            
            // PDF meta verilerini al
            guard let document = PDFDocument(url: destURL) else { return }
            let pageCount = document.pageCount
            let fileSize = try FileManager.default.attributesOfItem(atPath: destURL.path)[.size] as? Int64 ?? 0
            
            // PDFSourceModel oluştur
            let source = PDFSourceModel(
                fileName: fileName,
                filePath: destURL.path,
                fileSize: fileSize,
                pageCount: pageCount,
                subject: selectedSubject,
                examCategory: selectedCategory
            )
            modelContext.insert(source)
            try modelContext.save()
            
            // Parse et
            Task {
                do {
                    let result = try await pdfParser.parsePDF(
                        at: destURL,
                        subject: selectedSubject,
                        examCategory: selectedCategory
                    )
                    
                    await MainActor.run {
                        self.parsingResult = result
                        self.showParsingDetail = true
                    }
                } catch {
                    await MainActor.run {
                        source.parsingStatus = .failed
                        source.parsingError = error.localizedDescription
                        try? modelContext.save()
                    }
                }
            }
            
        } catch {
            print("PDF kopyalama hatası: \(error)")
        }
    }
    
    private func saveParsedQuestions(_ result: PDFParserService.ParsedPDFResult) {
        guard let source = pdfSources.first(where: { $0.fileName == result.fileName }) else { return }
        
        source.parsingStatus = result.parsingWarnings.isEmpty ? .completed : .partial
        source.totalQuestionsFound = result.questions.count
        source.successfullyParsed = result.questions.filter { $0.confidence > 0.5 }.count
        
        for parsedQ in result.questions {
            let options = parsedQ.options.enumerated().map { index, opt in
                OptionModel(text: opt.text, order: index, imageData: opt.imageData)
            }
            
            let question = QuestionModel(
                questionText: parsedQ.questionText,
                questionType: parsedQ.questionType,
                options: options,
                correctAnswerIndex: parsedQ.correctAnswerIndex,
                explanation: parsedQ.explanation,
                difficulty: .medium,
                estimatedTimeSeconds: 90,
                tags: [],
                pdfSource: source,
                parsingConfidence: parsedQ.confidence
            )
            
            // Learning outcomes ve topics burada eklenebilir (manuel veya AI ile)
            modelContext.insert(question)
        }
        
        try? modelContext.save()
        
        // Sonuç view'ını kapat
        showParsingDetail = false
        parsingResult = nil
    }
    
    private func deletePDFSource(_ source: PDFSourceModel) {
        // Dosyayı da sil
        try? FileManager.default.removeItem(atPath: source.filePath)
        modelContext.delete(source)
        try? modelContext.save()
    }
}

// MARK: - PDF Source Row

struct PDFSourceRow: View {
    let source: PDFSourceModel
    
    var body: some View {
        HStack(spacing: 12) {
            // Dosya ikonu
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.red.opacity(0.15))
                    .frame(width: 50, height: 50)
                Image(systemName: "doc.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(source.fileName)
                    .font(.subheadline)
                    .lineLimit(1)
                
                HStack(spacing: 12) {
                    Label("\(source.pageCount) sayfa", systemImage: "doc.on.doc")
                    Label(formatFileSize(source.fileSize), systemImage: "doc")
                    if let subject = source.subject {
                        Text(subject.rawValue)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                
                // Parsing durumu
                HStack {
                    parsingStatusBadge
                    Text(source.importedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Soru sayısı
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(source.successfullyParsed) / \(source.totalQuestionsFound)")
                    .font(.headline)
                    .foregroundStyle(.blue)
                Text("Soru")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
    
    private var parsingStatusBadge: some View {
        Group {
            switch source.parsingStatus {
            case .pending:
                Label("Bekliyor", systemImage: "clock")
                    .foregroundStyle(.orange)
            case .processing:
                Label("İşleniyor", systemImage: "gear")
                    .foregroundStyle(.blue)
            case .completed:
                Label("Tamam", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .partial:
                Label("Kısmi", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            case .failed:
                Label("Hata", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
            case .needsReview:
                Label("Gözden Geçir", systemImage: "eye")
                    .foregroundStyle(.blue)
            }
        }
        .font(.caption)
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Parsing Result View

struct ParsingResultView: View {
    let result: PDFParserService.ParsedPDFResult
    let onSave: (PDFParserService.ParsedPDFResult) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var showWarnings = false
    @State private var selectedQuestionIndex: Int = 0
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Özet başlık
                resultHeader
                
                // Uyarılar
                if !result.parsingWarnings.isEmpty {
                    Button(action: { showWarnings.toggle() }) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("\(result.parsingWarnings.count) Uyarı - Görüntüle")
                            Spacer()
                            Image(systemName: showWarnings ? "chevron.up" : "chevron.down")
                        }
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding()
                        .background(Color.orange.opacity(0.1))
                    }
                }
                
                // Soru listesi
                List {
                    ForEach(Array(result.questions.enumerated()), id: \.offset) { index, question in
                        ParsedQuestionRow(
                            question: question,
                            index: index + 1,
                            isSelected: selectedQuestionIndex == index
                        ) {
                            selectedQuestionIndex = index
                        }
                    }
                }
                
                // Kaydet butonu
                saveButton
            }
            .navigationTitle("Ayrıştırma Sonucu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
            }
            .sheet(isPresented: $showWarnings) {
                WarningListView(warnings: result.parsingWarnings)
            }
        }
    }
    
    private var resultHeader: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.fileName)
                        .font(.headline)
                    Text("\(result.pageCount) sayfa • \(result.examCategory.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let subject = result.subject {
                    Text(subject.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
            
            Divider()
            
            HStack(spacing: 20) {
                ResultStat(label: "Bulunan Soru", value: "\(result.questions.count)", color: .blue)
                ResultStat(label: "Cevaplı", value: "\(result.questions.filter { $0.correctAnswerIndex != nil }.count)", color: .green)
                ResultStat(label: "Ort. Güven", value: String(format: "%.0f%%", result.questions.map { $0.confidence }.reduce(0, +) / Double(max(1, result.questions.count)) * 100), color: .orange)
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }
    
    private var saveButton: some View {
        Button(action: {
            onSave(result)
            dismiss()
        }) {
            Text("Soruları Kaydet ve İçe Aktar")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding()
        .background(Color(.systemBackground))
    }
}

struct ResultStat: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold()).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ParsedQuestionRow: View {
    let question: PDFParserService.ParsedQuestion
    let index: Int
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Soru \(index)")
                        .font(.subheadline.bold())
                    Spacer()
                    confidenceBadge
                    if question.correctAnswerIndex != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                
                Text(question.questionText)
                    .font(.body)
                    .lineLimit(3)
                    .foregroundStyle(.primary)
                
                HStack(spacing: 8) {
                    ForEach(Array(question.options.enumerated()), id: \.offset) { optIndex, option in
                        Text("\(option.letter)")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.systemGray5))
                            .clipShape(Capsule())
                    }
                    if question.options.count > 5 {
                        Text("+\(question.options.count - 5) daha")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
    }
    
    private var confidenceBadge: some View {
        let color: Color = question.confidence > 0.7 ? .green : (question.confidence > 0.4 ? .orange : .red)
        return Text(String(format: "%.0f%%", question.confidence * 100))
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

struct WarningListView: View {
    let warnings: [String]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List(warnings, id: \.self) { warning in
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(warning)
                }
            }
            .navigationTitle("Parsing Uyarıları")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }
}