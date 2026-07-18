import SwiftUI
import SwiftData

// MARK: - Wrong Questions View (Yanlış/Boş Sorular Bankası)

struct WrongQuestionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        sort: [SortDescriptor(\WrongQuestionBankModel.lastWrongDate, order: .reverse)],
        animation: .default
    ) private var wrongQuestions: [WrongQuestionBankModel]
    
    @State private var filter: FilterOption = .all
    @State private var selectedSubject: Subject? = nil
    @State private var showReviewSession = false
    @State private var searchText = ""
    
    enum FilterOption: String, CaseIterable, Identifiable {
        case all = "Hepsi"
        case unresolved = "Çözülmeyen"
        case resolved = "Çözülen"
        case due = "Tekrar Zamanı"
        var id: String { rawValue }
    }
    
    private var filteredQuestions: [WrongQuestionBankModel] {
        var result = wrongQuestions
        
        // Arama
        if !searchText.isEmpty {
            result = result.filter { entry in
                entry.question?.questionText.localizedCaseInsensitiveContains(searchText) == true
            }
        }
        
        // Ders filtresi
        if let subject = selectedSubject {
            result = result.filter { $0.question?.pdfSource?.subject == subject }
        }
        
        // Durum filtresi
        switch filter {
        case .unresolved:
            result = result.filter { !$0.isResolved }
        case .resolved:
            result = result.filter { $0.isResolved }
        case .due:
            let now = Date()
            result = result.filter { !$0.isResolved && ($0.nextReviewDate ?? .distantFuture) <= now }
        case .all:
            break
        }
        
        return result
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filtre çubuğu
                filterBar
                
                // Liste
                if filteredQuestions.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Yanlış/Boş Sorularım")
            .searchable(text: $searchText, prompt: "Soru metninde ara...")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { startReviewAll() }) {
                            Label("Tümünü Tekrar Et (\(wrongQuestions.filter { !$0.isResolved }.count))", systemImage: "play.circle")
                        }
                        .disabled(wrongQuestions.filter { !$0.isResolved }.isEmpty)
                        
                        Button(action: { startReviewDue() }) {
                            Label("Zamanı Gelenleri Tekrar Et", systemImage: "clock")
                        }
                        .disabled(wrongQuestions.filter { !$0.isResolved && ($0.nextReviewDate ?? .distantFuture) <= Date() }.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }
    
    private var filterBar: some View {
        VStack(spacing: 12) {
            // Filtre butonları
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FilterOption.allCases) { option in
                        FilterChip(
                            title: option.rawValue,
                            isSelected: filter == option,
                            count: countForFilter(option)
                        ) {
                            filter = option
                        }
                    }
                }
                .padding(.horizontal)
            }
            
            // Ders filtresi
            if !subjectCounts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(
                            title: "Tümü",
                            isSelected: selectedSubject == nil,
                            count: filteredQuestions.count
                        ) {
                            selectedSubject = nil
                        }
                        
                        ForEach(subjectCounts, id: \.subject) { item in
                            FilterChip(
                                title: item.subject.rawValue,
                                isSelected: selectedSubject == item.subject,
                                count: item.count
                            ) {
                                selectedSubject = item.subject
                            }
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
            filter == .all ? "Henüz Yanlış/Boş Soru Yok" : "Bu Filtrede Soru Yok",
            systemImage: filter == .all ? "checkmark.circle.fill" : "magnifyingglass",
            description: Text(filter == .all 
                ? "Soruları çözerken yaptığınız hatalar ve boş bıraktığınız sorular otomatik olarak buraya eklenir." 
                : "Farklı bir filtre deneyin veya arama yapın.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var list: some View {
        List {
            ForEach(filteredQuestions) { entry in
                WrongQuestionRow(entry: entry) { action in
                    handleAction(action, for: entry)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
    
    private func countForFilter(_ option: FilterOption) -> Int {
        switch option {
        case .all: return wrongQuestions.count
        case .unresolved: return wrongQuestions.filter { !$0.isResolved }.count
        case .resolved: return wrongQuestions.filter { $0.isResolved }.count
        case .due: 
            let now = Date()
            return wrongQuestions.filter { !$0.isResolved && ($0.nextReviewDate ?? .distantFuture) <= now }.count
        }
    }
    
    private var subjectCounts: [(subject: Subject, count: Int)] {
        let subjects = Set(wrongQuestions.compactMap { $0.question?.pdfSource?.subject })
        return subjects.compactMap { subject in
            let count = wrongQuestions.filter { $0.question?.pdfSource?.subject == subject }.count
            return count > 0 ? (subject, count) : nil
        }.sorted { $0.1 > $1.1 }
    }
    
    private func handleAction(_ action: WrongQuestionRow.Action, for entry: WrongQuestionBankModel) {
        switch action {
        case .review:
            startReview(for: entry)
        case .markResolved:
            entry.isResolved = true
            entry.resolvedAt = Date()
            try? modelContext.save()
        case .markUnresolved:
            entry.isResolved = false
            entry.resolvedAt = nil
            try? modelContext.save()
        case .delete:
            modelContext.delete(entry)
            try? modelContext.save()
        }
    }
    
    private func startReview(for entry: WrongQuestionBankModel) {
        guard let question = entry.question else { return }
        let session = SolveSessionViewModel.createSession(
            name: "Tekrar: \(question.questionText.prefix(30))...",
            subject: question.pdfSource?.subject,
            examCategory: .topicTest,
            questionIds: [question.id],
            modelContext: modelContext
        )
        // Navigate to solve view
    }
    
    private func startReviewAll() {
        let unresolved = wrongQuestions.filter { !$0.isResolved }
        let questionIds = unresolved.compactMap { $0.question?.id }
        guard !questionIds.isEmpty else { return }
        
        let session = SolveSessionViewModel.createSession(
            name: "Tüm Yanlışları Tekrar",
            subject: nil,
            examCategory: .topicTest,
            questionIds: questionIds,
            modelContext: modelContext
        )
    }
    
    private func startReviewDue() {
        let now = Date()
        let due = wrongQuestions.filter { !$0.isResolved && ($0.nextReviewDate ?? .distantFuture) <= now }
        let questionIds = due.compactMap { $0.question?.id }
        guard !questionIds.isEmpty else { return }
        
        let session = SolveSessionViewModel.createSession(
            name: "Zamanı Gelenleri Tekrar",
            subject: nil,
            examCategory: .topicTest,
            questionIds: questionIds,
            modelContext: modelContext
        )
    }
}

// MARK: - Wrong Question Row

struct WrongQuestionRow: View {
    let entry: WrongQuestionBankModel
    let onAction: (Action) -> Void
    
    enum Action {
        case review
        case markResolved
        case markUnresolved
        case delete
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Soru metni
            if let question = entry.question {
                Text(question.questionText)
                    .font(.body)
                    .lineLimit(3)
                
                // Meta bilgi
                HStack(spacing: 12) {
                    if let subject = question.pdfSource?.subject {
                        Label(subject.rawValue, systemImage: subject.icon)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    
                    // Durum badge'leri
                    HStack(spacing: 4) {
                        Image(systemName: entry.isResolved ? "checkmark.circle.fill" : "xmark.circle.fill")
                        Text(entry.isResolved ? "Çözüldü" : "Çözülmedi")
                    }
                    .font(.caption)
                    .foregroundStyle(entry.isResolved ? .green : .red)
                    
                    if let nextReview = entry.nextReviewDate {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                            Text(nextReview <= Date() ? "Tekrar zamanı!" : "\(nextReview, style: .relative) sonra")
                        }
                        .font(.caption)
                        .foregroundStyle(nextReview <= Date() ? .orange : .secondary)
                    }
                    
                    Spacer()
                    
                    Text("\(entry.wrongAttemptCount) kez yanlış")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                // Aksiyon butonları
                HStack(spacing: 8) {
                    Button(action: { onAction(.review) }) {
                        Label("Tekrar Çöz", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    
                    Button(action: { 
                        onAction(entry.isResolved ? .markUnresolved : .markResolved) 
                    }) {
                        Label(entry.isResolved ? "Çözülmedi" : "Çözüldü", 
                              systemImage: entry.isResolved ? "xmark.circle" : "checkmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundStyle(entry.isResolved ? .red : .green)
                }
            }
        }
        .padding(.vertical, 8)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                onAction(.delete)
            } label: {
                Label("Sil", systemImage: "trash")
            }
        }
    }
}

// MARK: - Filter Chip

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
            .shadow(color: .black.opacity(isSelected ? 0.1 : 0), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }
}