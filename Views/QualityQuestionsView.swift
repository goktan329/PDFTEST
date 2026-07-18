import SwiftUI
import SwiftData

// MARK: - Quality Questions View (Kaliteli Sorular Arşivi)

struct QualityQuestionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        sort: [SortDescriptor(\QualityQuestionModel.addedAt, order: .reverse)],
        animation: .default
    ) private var qualityQuestions: [QualityQuestionModel]
    
    @State private var searchText = ""
    @State private var selectedSubject: Subject? = nil
    @State private var sortOption: SortOption = .dateAdded
    @State private var showSolveSession = false
    
    enum SortOption: String, CaseIterable, Identifiable {
        case dateAdded = "Eklenme Tarihi"
        case rating = "Puan"
        case difficulty = "Zorluk"
        case subject = "Ders"
        var id: String { rawValue }
    }
    
    private var filteredQuestions: [QualityQuestionModel] {
        var result = qualityQuestions
        
        if !searchText.isEmpty {
            result = result.filter { entry in
                entry.question?.questionText.localizedCaseInsensitiveContains(searchText) == true
            }
        }
        
        if let subject = selectedSubject {
            result = result.filter { $0.question?.pdfSource?.subject == subject }
        }
        
        switch sortOption {
        case .dateAdded:
            result.sort { $0.addedAt > $1.addedAt }
        case .rating:
            result.sort { $0.userRating > $1.userRating }
        case .difficulty:
            result.sort { ($0.question?.difficulty ?? .medium) > ($1.question?.difficulty ?? .medium) }
        case .subject:
            result.sort { ($0.question?.pdfSource?.subject?.rawValue ?? "") < ($1.question?.pdfSource?.subject?.rawValue ?? "") }
        }
        
        return result
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Toolbar
                toolbarView
                
                // List
                if filteredQuestions.isEmpty {
                    emptyState
                } else {
                    listView
                }
            }
            .navigationTitle("Kaliteli Sorular")
            .searchable(text: $searchText, prompt: "Soru ara...")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { startSolveAll() }) {
                            Label("Tümünü Çöz (\(qualityQuestions.count))", systemImage: "play.circle")
                        }
                        .disabled(qualityQuestions.isEmpty)
                        
                        Divider()
                        
                        Picker("Sırala", selection: $sortOption) {
                            ForEach(SortOption.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }
    
    private var toolbarView: some View {
        VStack(spacing: 8) {
            // İstatistik özeti
            HStack(spacing: 20) {
                StatChip(title: "Toplam", value: "\(qualityQuestions.count)", color: .blue)
                StatChip(title: "Ort. Puan", value: averageRating, color: .yellow)
                if let subject = mostCommonSubject {
                    StatChip(title: "En Çok", value: subject.rawValue, color: .green)
                }
            }
            
            // Ders filtresi
            if !subjectCounts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(
                            title: "Tümü",
                            isSelected: selectedSubject == nil,
                            count: filteredQuestions.count
                        ) { selectedSubject = nil }
                        
                        ForEach(subjectCounts, id: \.subject) { item in
                            FilterChip(
                                title: item.subject.rawValue,
                                isSelected: selectedSubject == item.subject,
                                count: item.count
                            ) { selectedSubject = item.subject }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
    }
    
    private var emptyState: some View {
        ContentUnavailableView(
            qualityQuestions.isEmpty ? "Henüz Kaliteli Soru Yok" : "Bu Filtrede Soru Yok",
            systemImage: "star",
            description: Text(qualityQuestions.isEmpty
                ? "Soru çözerken yıldız işaretine basarak kaliteli bulduğunuz soruları buraya ekleyin.\n\nBu arşivi sınav öncesi tekrar için kullanın."
                : "Farklı bir filtre deneyin.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var listView: some View {
        List {
            ForEach(filteredQuestions) { entry in
                QualityQuestionRow(entry: entry)
            }
        }
        .listStyle(.insetGrouped)
    }
    
    private var averageRating: String {
        guard !qualityQuestions.isEmpty else { return "0" }
        let avg = Double(qualityQuestions.map { $0.userRating }.reduce(0, +)) / Double(qualityQuestions.count)
        return String(format: "%.1f", avg)
    }
    
    private var mostCommonSubject: Subject? {
        let subjects = qualityQuestions.compactMap { $0.question?.pdfSource?.subject }
        guard !subjects.isEmpty else { return nil }
        return Dictionary(grouping: subjects, by: { $0 }).max { $0.value.count < $1.value.count }?.key
    }
    
    private var subjectCounts: [(subject: Subject, count: Int)] {
        let subjects = qualityQuestions.compactMap { $0.question?.pdfSource?.subject }
        return Dictionary(grouping: subjects, by: { $0 })
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 > $1.1 }
    }
    
    private func startSolveAll() {
        let questionIds = qualityQuestions.compactMap { $0.question?.id }
        guard !questionIds.isEmpty else { return }
        
        let session = SolveSessionViewModel.createSession(
            name: "Kaliteli Sorular Arşivi",
            subject: nil,
            examCategory: .topicTest,
            questionIds: questionIds,
            modelContext: modelContext
        )
    }
}

// MARK: - Quality Question Row

struct QualityQuestionRow: View {
    @Environment(\.modelContext) private var modelContext
    let entry: QualityQuestionModel
    
    @State private var showDetail = false
    @State private var showEditRating = false
    
    var body: some View {
        Button(action: { showDetail = true }) {
            VStack(alignment: .leading, spacing: 8) {
                // Soru metni
                if let question = entry.question {
                    Text(question.questionText)
                        .font(.body)
                        .lineLimit(3)
                        .foregroundStyle(.primary)
                    
                    // Meta bilgiler
                    HStack(spacing: 12) {
                        // Puan
                        HStack(spacing: 2) {
                            ForEach(1...5, id: \.self) { star in
                                Image(systemName: star <= entry.userRating ? "star.fill" : "star")
                                    .font(.caption)
                                    .foregroundStyle(star <= entry.userRating ? .yellow : .secondary)
                            }
                        }
                        
                        // Ders
                        if let subject = question.pdfSource?.subject {
                            Label(subject.rawValue, systemImage: subject.icon)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15))
                                .clipShape(Capsule())
                        }
                        
                        // Zorluk
                        if let difficulty = question.difficulty {
                            Text(difficultyLabel(difficulty))
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(difficultyColor(difficulty).opacity(0.2))
                                .foregroundStyle(difficultyColor(difficulty))
                                .clipShape(Capsule())
                        }
                        
                        Spacer()
                        
                        // Eklenme tarihi
                        Text(entry.addedAt, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    
                    // Kullanıcı etiketleri
                    if !entry.userTags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(entry.userTags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(Color.purple.opacity(0.15))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    
                    // Not
                    if let note = entry.note, !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                deleteEntry()
            } label: {
                Label("Arşivden Kaldır", systemImage: "star.slash")
            }
            
            Button {
                showEditRating = true
            } label: {
                Label("Puanla", systemImage: "star")
            }
            .tint(.yellow)
        }
        .sheet(isPresented: $showDetail) {
            QualityQuestionDetailView(entry: entry)
        }
        .sheet(isPresented: $showEditRating) {
            EditQualityEntryView(entry: entry)
        }
    }
    
    private func deleteEntry() {
        modelContext.delete(entry)
        try? modelContext.save()
    }
    
    private func difficultyLabel(_ d: Difficulty) -> String {
        switch d {
        case .easy: return "🟢 Kolay"
        case .medium: return "🟡 Orta"
        case .hard: return "🔴 Zor"
        }
    }
    
    private func difficultyColor(_ d: Difficulty) -> Color {
        switch d {
        case .easy: return .green
        case .medium: return .orange
        case .hard: return .red
        }
    }
}

// MARK: - Quality Question Detail View

struct QualityQuestionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let entry: QualityQuestionModel
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let question = entry.question {
                        // Soru
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Soru")
                                .font(.headline)
                            Text(question.questionText)
                                .font(.body)
                            
                            // Şıklar
                            if !question.options.isEmpty {
                                VStack(spacing: 8) {
                                    ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                                        HStack {
                                            Text("\(question.optionLetters[index])")
                                                .font(.caption)
                                                .fontWeight(.bold)
                                                .frame(width: 24)
                                            Text(option.text)
                                                .font(.body)
                                            Spacer()
                                            if question.correctAnswerIndex == index {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(.green)
                                            }
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color(.systemGray6))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
                            
                            // Resmi açıklama
                            if let explanation = question.explanation {
                                Divider()
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Resmi Açıklama")
                                        .font(.headline)
                                    Text(explanation)
                                        .font(.body)
                                }
                            }
                            
                            // Kullanıcı notu
                            if let userNote = question.userSolutionNote {
                                Divider()
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Kendi Çözüm Notunuz")
                                        .font(.headline)
                                    Text(userNote)
                                        .font(.body)
                                        .foregroundStyle(.blue)
                                }
                            }
                            
                            // AI çözümü
                            if let aiSolution = question.aiSolution {
                                Divider()
                                VStack(alignment: .leading, spacing: 8) {
                                    Label("AI Çözümü", systemImage: "brain.head.profile")
                                        .font(.headline)
                                    Text(aiSolution)
                                        .font(.body)
                                }
                            }
                        }
                    }
                    
                    // Arşiv bilgileri
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Arşiv Bilgileri")
                            .font(.headline)
                        
                        InfoRow(label: "Eklenme Tarihi", value: entry.addedAt.formatted(date: .complete, time: .shortened))
                        InfoRow(label: "Puan", value: "\(entry.userRating) / 5")
                        InfoRow(label: "Etiketler", value: entry.userTags.isEmpty ? "Yok" : entry.userTags.joined(separator: ", "))
                        if let note = entry.note {
                            InfoRow(label: "Not", value: note)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Soru Detayı")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.body)
    }
}

// MARK: - Edit Quality Entry View

struct EditQualityEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let entry: QualityQuestionModel
    
    @State private var rating: Int
    @State private var tagsText: String
    @State private var note: String
    
    init(entry: QualityQuestionModel) {
        self.entry = entry
        _rating = State(initialValue: entry.userRating)
        _tagsText = State(initialValue: entry.userTags.joined(separator: ", "))
        _note = State(initialValue: entry.note ?? "")
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Puan (1-5)") {
                    Stepper("\(rating) yıldız", value: $rating, in: 1...5)
                    HStack {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= rating ? "star.fill" : "star")
                                .foregroundStyle(star <= rating ? .yellow : .secondary)
                                .onTapGesture { rating = star }
                        }
                    }
                }
                
                Section("Etiketler (virgülle ayrılmış)") {
                    TextField("örn: zor, ipucu, formül", text: $tagsText)
                }
                
                Section("Not") {
                    TextEditor(text: $note)
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle("Düzenle")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { save() }
                }
            }
        }
    }
    
    private func save() {
        entry.userRating = rating
        entry.userTags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        entry.note = note.isEmpty ? nil : note
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Stat Chip

struct StatChip: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Filter Chip (Reuse)

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let count: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("\(count)")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(isSelected ? Color.white.opacity(0.3) : Color.primary.opacity(0.15))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color(.systemBackground))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}