import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Main App Entry

@main
struct OfflineTestApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            SubjectModel.self,
            TopicModel.self,
            LearningOutcomeModel.self,
            PDFSourceModel.self,
            QuestionModel.self,
            OptionModel.self,
            UserAttemptModel.self,
            SolveSessionModel.self,
            WrongQuestionBankModel.self,
            QualityQuestionModel.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("ModelContainer oluşturulamadı: \(error)")
        }
    }()
    
    @StateObject private var pdfParser = PDFParserService.shared
    @StateObject private var llmService = LLMService.shared
    
    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(pdfParser)
                .environmentObject(llmService)
                .modelContainer(sharedModelContainer)
        }
    }
}

// MARK: - Root Tab View

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab = 0
    @State private var showPDFImporter = false
    @State private var showModelDownloader = false
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Ana Sayfa / Dashboard
            DashboardView()
                .tabItem {
                    Label("Ana Sayfa", systemImage: "house.fill")
                }
                .tag(0)
            
            // Dersler ve Konular
            SubjectsView()
                .tabItem {
                    Label("Dersler", systemImage: "book.fill")
                }
                .tag(1)
            
            // PDF Yükle
            PDFImportView()
                .tabItem {
                    Label("PDF Yükle", systemImage: "doc.badge.plus")
                }
                .tag(2)
            
            // Yanlış/Boş Sorular
            WrongQuestionsView()
                .tabItem {
                    Label("Yanlışlarım", systemImage: "xmark.circle.fill")
                }
                .tag(3)
            
            // Ayarlar
            SettingsView()
                .tabItem {
                    Label("Ayarlar", systemImage: "gear")
                }
                .tag(4)
        }
        .accentColor(.blue)
    }
}

// MARK: - Dashboard View

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SolveSessionModel.startedAt, order: .reverse) private var sessions: [SolveSessionModel]
    @Query private var wrongQuestions: [WrongQuestionBankModel]
    @Query private var qualityQuestions: [QualityQuestionModel]
    @Query private var pdfSources: [PDFSourceModel]
    
    @State private var showCreateSession = false
    @State private var selectedSubject: Subject? = nil
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Hoş geldin / Özet kartı
                    summaryCard
                    
                    // Hızlı erişim butonları
                    quickActions
                    
                    // Son oturumlar
                    if !sessions.isEmpty {
                        recentSessionsSection
                    }
                    
                    // Yanlış soru sayısı
                    if !wrongQuestions.isEmpty {
                        wrongQuestionsCard
                    }
                    
                    // Kaliteli sorular
                    if !qualityQuestions.isEmpty {
                        qualityQuestionsCard
                    }
                }
                .padding()
            }
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        ForEach(Subject.allCases, id: \.self) { subject in
                            Button(subject.rawValue) { selectedSubject = subject; showCreateSession = true }
                        }
                        Divider()
                        Button("Tüm Dersler") { selectedSubject = nil; showCreateSession = true }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                }
            }
            .sheet(isPresented: $showCreateSession) {
                CreateSessionSheet(selectedSubject: selectedSubject)
            }
        }
    }
    
    private var summaryCard: some View {
        let totalSessions = sessions.count
        let completedSessions = sessions.filter { $0.isCompleted }.count
        let avgNet = sessions.filter { $0.isCompleted }.map { $0.netScore }.reduce(0, +) / Double(max(1, completedSessions))
        let totalQuestions = sessions.flatMap { $0.attempts }.count
        let correctQuestions = sessions.flatMap { $0.attempts }.filter { $0.status == .correct }.count
        
        return VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Merhaba! 👋")
                        .font(.title2).bold()
                    Text("Hazır mısın bugün?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 50))
                    .foregroundStyle(.blue.gradient)
            }
            
            Divider()
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatCard(title: "Toplam Deneme", value: "\(totalSessions)", icon: "doc.text.fill", color: .blue)
                StatCard(title: "Tamamlanan", value: "\(completedSessions)", icon: "checkmark.circle.fill", color: .green)
                StatCard(title: "Çözülen Soru", value: "\(totalQuestions)", icon: "questionmark.circle.fill", color: .orange)
                StatCard(title: "Ortalama Net", value: String(format: "%.2f", avgNet), icon: "function", color: .purple)
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
    }
    
    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hızlı İşlemler")
                .font(.headline)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                QuickActionButton(
                    title: "Yeni Deneme Başlat",
                    icon: "play.circle.fill",
                    color: .green
                ) { showCreateSession = true }
                
                QuickActionButton(
                    title: "Yanlışları Tekrar Et",
                    icon: "arrow.clockwise.circle.fill",
                    color: .orange
                ) { startWrongQuestionsReview() }
                .disabled(wrongQuestions.isEmpty)
                
                QuickActionButton(
                    title: "Kaliteli Soruları Çöz",
                    icon: "star.circle.fill",
                    color: .yellow
                ) { startQualityQuestions() }
                .disabled(qualityQuestions.isEmpty)
                
                QuickActionButton(
                    title: "PDF Yükle",
                    icon: "doc.badge.plus",
                    color: .blue
                ) { /* Tab değiştir */ }
            }
        }
    }
    
    private var recentSessionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Son Denemeler")
                    .font(.headline)
                Spacer()
                NavigationLink("Tümü") { SessionHistoryView() }
                    .font(.subheadline)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(sessions.prefix(5)) { session in
                        SessionCard(session: session)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }
    
    private var wrongQuestionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("\(wrongQuestions.count) Yanlış/Boş Soru", systemImage: "xmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Spacer()
                Button("Hepsini Gör") { /* Navigate */ }
                    .font(.subheadline)
            }
            
            Text("Bu soruları düzenli tekrarlayarak netlerinizi artırın. Spaced repetition algoritması ile size en uygun zamanlarda hatırlatılacak.")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Button(action: startWrongQuestionsReview) {
                Label("Şimdi Tekrar Et", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private var qualityQuestionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("\(qualityQuestions.count) Kaliteli Soru", systemImage: "star.fill")
                    .font(.headline)
                    .foregroundStyle(.yellow)
                Spacer()
            }
            
            Button(action: startQualityQuestions) {
                Label("Arşivi Gör / Çöz", systemImage: "book.closed")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private func startWrongQuestionsReview() {
        if let session = SolveSessionViewModel.createSessionFromWrongQuestions(
            subject: nil,
            modelContext: modelContext
        ) {
            // Navigate to solve view - handled by session creation
        }
    }
    
    private func startQualityQuestions() {
        if let session = SolveSessionViewModel.createSessionFromQualityQuestions(
            subject: nil,
            modelContext: modelContext
        ) {
            // Navigate
        }
    }
}

// MARK: - Supporting Views

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.title.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(color)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, minHeight: 100)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

struct SessionCard: View {
    let session: SolveSessionModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.name)
                .font(.subheadline.bold())
                .lineLimit(1)
            
            HStack(spacing: 12) {
                Label("\(session.correctCount)", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                Label("\(session.wrongCount)", systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                Label(String(format: "%.2f", session.netScore), systemImage: "function")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
            
            Text(session.startedAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.secondary)
            
            if session.isCompleted {
                Text("Tamamlandı")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.2))
                    .foregroundStyle(.green)
                    .clipShape(Capsule())
            } else {
                Text("Devam Ediyor")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())
            }
        }
        .padding(16)
        .frame(width: 180)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

// MARK: - Create Session Sheet

struct CreateSessionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var questions: [QuestionModel]
    
    let selectedSubject: Subject?
    
    @State private var sessionName = ""
    @State private var examCategory: ExamCategory = .topicTest
    @State private var questionCount = 20
    @State private var selectedTopics: Set<UUID> = []
    @State private var selectedOutcomes: Set<UUID> = []
    @State private var showTopicPicker = false
    @State private var showOutcomePicker = false
    
    private var filteredQuestions: [QuestionModel] {
        questions.filter { q in
            let subjectMatch = selectedSubject == nil || q.pdfSource?.subject == selectedSubject
            let topicMatch = selectedTopics.isEmpty || q.topics.contains { selectedTopics.contains($0.id) }
            let outcomeMatch = selectedOutcomes.isEmpty || q.learningOutcomes.contains { selectedOutcomes.contains($0.id) }
            return subjectMatch && topicMatch && outcomeMatch
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Oturum Bilgileri") {
                    TextField("Oturum Adı (örn: Matematik Deneme 1)", text: $sessionName)
                    
                    Picker("Tür", selection: $examCategory) {
                        ForEach(ExamCategory.allCases) { cat in
                            Text(cat.rawValue).tag(cat)
                        }
                    }
                    
                    Stepper("Soru Sayısı: \(questionCount)", value: $questionCount, in: 5...100, step: 5)
                }
                
                Section("Filtreler") {
                    if let subject = selectedSubject {
                        HStack {
                            Image(systemName: subject.icon)
                            Text(subject.rawValue)
                            Spacer()
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                    
                    Button(action: { showTopicPicker = true }) {
                        HStack {
                            Label("Konu Seç", systemImage: "list.bullet")
                            Spacer()
                            Text("\(selectedTopics.count) seçili")
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Button(action: { showOutcomePicker = true }) {
                        HStack {
                            Label("Kazanım Seç", systemImage: "target")
                            Spacer()
                            Text("\(selectedOutcomes.count) seçili")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Section("Önizleme") {
                    Text("\(filteredQuestions.count) uygun soru bulundu")
                        .foregroundStyle(.secondary)
                    
                    if filteredQuestions.count < questionCount {
                        Text("⚠️ Yeterli soru yok, filtreleri genişletin")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Yeni Çözüm Oturumu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Oluştur") { createSession() }
                        .disabled(sessionName.isEmpty || filteredQuestions.count < 5)
                }
            }
            .sheet(isPresented: $showTopicPicker) { TopicPickerSheet(selectedIDs: $selectedTopics, subject: selectedSubject) }
            .sheet(isPresented: $showOutcomePicker) { OutcomePickerSheet(selectedIDs: $selectedOutcomes, subject: selectedSubject) }
        }
    }
    
    private func createSession() {
        let shuffled = filteredQuestions.shuffled()
        let selected = Array(shuffled.prefix(questionCount))
        let questionIds = selected.map { $0.id }
        
        let session = SolveSessionViewModel.createSession(
            name: sessionName,
            subject: selectedSubject,
            examCategory: examCategory,
            questionIds: questionIds,
            modelContext: modelContext
        )
        
        dismiss()
        // Navigate to solve view - would need navigation path
    }
}

// MARK: - Placeholder Sheets

struct TopicPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Binding var selectedIDs: Set<UUID>
    let subject: Subject?
    
    @Query private var topics: [TopicModel]
    
    private var filteredTopics: [TopicModel] {
        if let subject = subject {
            return topics.filter { $0.subject?.subjectType == subject }
        }
        return topics
    }
    
    var body: some View {
        NavigationStack {
            List(filteredTopics) { topic in
                Button(action: {
                    if selectedIDs.contains(topic.id) {
                        selectedIDs.remove(topic.id)
                    } else {
                        selectedIDs.insert(topic.id)
                    }
                }) {
                    HStack {
                        Text(topic.name)
                        Spacer()
                        if selectedIDs.contains(topic.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
            .navigationTitle("Konu Seç")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Tamam") { dismiss() }
                }
            }
        }
    }
}

struct OutcomePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Binding var selectedIDs: Set<UUID>
    let subject: Subject?
    
    @Query private var outcomes: [LearningOutcomeModel]
    
    private var filteredOutcomes: [LearningOutcomeModel] {
        if let subject = subject {
            return outcomes.filter { $0.subject?.subjectType == subject }
        }
        return outcomes
    }
    
    var body: some View {
        NavigationStack {
            List(filteredOutcomes) { outcome in
                Button(action: {
                    if selectedIDs.contains(outcome.id) {
                        selectedIDs.remove(outcome.id)
                    } else {
                        selectedIDs.insert(outcome.id)
                    }
                }) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(outcome.code).font(.caption).foregroundStyle(.secondary)
                            Text(outcome.description).font(.body).lineLimit(2)
                        }
                        Spacer()
                        if selectedIDs.contains(outcome.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
            .navigationTitle("Kazanım Seç")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Tamam") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Session History View

struct SessionHistoryView: View {
    @Query(sort: \SolveSessionModel.startedAt, order: .reverse) private var sessions: [SolveSessionModel]
    
    var body: some View {
        List(sessions) { session in
            NavigationLink(destination: SessionDetailView(session: session)) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.name)
                        .font(.headline)
                    HStack {
                        Label("\(session.correctCount)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Label("\(session.wrongCount)", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Label(String(format: "%.2f", session.netScore), systemImage: "function")
                            .foregroundStyle(.blue)
                    }
                    .font(.caption)
                    Text(session.startedAt, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Deneme Geçmişi")
    }
}

struct SessionDetailView: View {
    let session: SolveSessionModel
    
    var body: some View {
        List {
            Section("Özet") {
                HStack {
                    Spacer()
                    VStack {
                        Text(String(format: "%.2f", session.netScore))
                            .font(.system(size: 48, weight: .bold))
                            .foregroundStyle(.blue)
                        Text("Net")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
                
                HStack {
                    StatRow(label: "Doğru", value: "\(session.correctCount)", color: .green)
                    StatRow(label: "Yanlış", value: "\(session.wrongCount)", color: .red)
                    StatRow(label: "Boş", value: "\(session.blankCount)", color: .orange)
                    StatRow(label: "Süre", value: formatDuration(session.durationSeconds), color: .blue)
                }
            }
            
            Section("Sorular") {
                ForEach(session.attempts) { attempt in
                    HStack {
                        Text("Soru \(attempt.attemptNumber)")
                        Spacer()
                        Image(systemName: statusIcon(attempt.status))
                            .foregroundStyle(statusColor(attempt.status))
                    }
                }
            }
        }
        .navigationTitle(session.name)
    }
    
    private func statusIcon(_ status: AnswerStatus) -> String {
        switch status {
        case .correct: return "checkmark.circle.fill"
        case .wrong: return "xmark.circle.fill"
        case .blank: return "circle.fill"
        case .unanswered: return "circle"
        }
    }
    
    private func statusColor(_ status: AnswerStatus) -> Color {
        switch status {
        case .correct: return .green
        case .wrong: return .red
        case .blank: return .orange
        case .unanswered: return .gray
        }
    }
    
    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

struct StatRow: View {
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