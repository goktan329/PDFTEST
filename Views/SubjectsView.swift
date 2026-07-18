import SwiftUI
import SwiftData

// MARK: - Subjects View (Dersler, Konular, Kazanımlar)

struct SubjectsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\SubjectModel.order), SortDescriptor(\SubjectModel.name)]) private var subjects: [SubjectModel]
    @Query private var topics: [TopicModel]
    @Query private var outcomes: [LearningOutcomeModel]
    @Query private var questions: [QuestionModel]
    
    @State private var showAddSubject = false
    @State private var selectedSubject: SubjectModel?
    @State private var showSubjectDetail = false
    
    var body: some View {
        NavigationStack {
            List {
                if subjects.isEmpty {
                    emptyState
                } else {
                    ForEach(subjects) { subject in
                        SubjectRow(
                            subject: subject,
                            topicCount: topics.filter { $0.subject?.id == subject.id }.count,
                            questionCount: questions.filter { q in
                                q.topics.contains { $0.subject?.id == subject.id }
                            }.count,
                            onTap: { selectedSubject = subject; showSubjectDetail = true }
                        )
                    }
                    .onDelete(perform: deleteSubjects)
                }
            }
            .navigationTitle("Dersler ve Konular")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showAddSubject = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddSubject) {
                AddSubjectSheet()
            }
            .sheet(item: $selectedSubject) { subject in
                SubjectDetailView(subject: subject)
            }
        }
    }
    
    private var emptyState: some View {
        ContentUnavailableView(
            "Henüz Ders Eklenmedi",
            systemImage: "book.closed",
            description: Text("Yeni ders eklemek için + butonuna basın.\nDersler, konular ve kazanımlar otomatik oluşturulur.")
        )
    }
    
    private func deleteSubjects(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(subjects[index])
        }
        try? modelContext.save()
    }
}

// MARK: - Subject Row

struct SubjectRow: View {
    let subject: SubjectModel
    let topicCount: Int
    let questionCount: Int
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Ders ikonu
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(hex: subject.colorHex).opacity(0.2))
                        .frame(width: 50, height: 50)
                    Image(systemName: subject.subjectType.icon)
                        .font(.title2)
                        .foregroundStyle(Color(hex: subject.colorHex))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(subject.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    HStack(spacing: 16) {
                        Label("\(topicCount) Konu", systemImage: "list.bullet")
                        Label("\(questionCount) Soru", systemImage: "questionmark.circle")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Subject Detail View

struct SubjectDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let subject: SubjectModel
    @Query private var topics: [TopicModel]
    @Query private var outcomes: [LearningOutcomeModel]
    @Query private var questions: [QuestionModel]
    
    @State private var showAddTopic = false
    @State private var showAddOutcome = false
    @State private var selectedTopic: TopicModel?
    
    private var subjectTopics: [TopicModel] {
        topics.filter { $0.subject?.id == subject.id }.sorted { $0.order < $1.order }
    }
    
    private var subjectOutcomes: [LearningOutcomeModel] {
        outcomes.filter { $0.subject?.id == subject.id }.sorted { $0.order < $1.order }
    }
    
    private var subjectQuestions: [QuestionModel] {
        questions.filter { q in
            q.topics.contains { $0.subject?.id == subject.id }
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Özet
                Section {
                    HStack(spacing: 20) {
                        StatBox(title: "Konular", value: "\(subjectTopics.count)", icon: "list.bullet", color: .blue)
                        StatBox(title: "Kazanımlar", value: "\(subjectOutcomes.count)", icon: "target", color: .green)
                        StatBox(title: "Sorular", value: "\(subjectQuestions.count)", icon: "questionmark.circle", color: .orange)
                    }
                }
                
                // Konular
                Section("Konular") {
                    if subjectTopics.isEmpty {
                        Text("Henüz konu eklenmemiş")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(subjectTopics) { topic in
                            TopicRow(
                                topic: topic,
                                questionCount: questions.filter { $0.topics.contains { $0.id == topic.id } }.count,
                                onTap: { selectedTopic = topic }
                            )
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                modelContext.delete(subjectTopics[index])
                            }
                            try? modelContext.save()
                        }
                    }
                    
                    Button(action: { showAddTopic = true }) {
                        Label("Yeni Konu Ekle", systemImage: "plus.circle")
                    }
                }
                
                // Kazanımlar
                Section("Kazanımlar") {
                    if subjectOutcomes.isEmpty {
                        Text("Henüz kazanım eklenmemiş")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(subjectOutcomes) { outcome in
                            OutcomeRow(outcome: outcome)
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                modelContext.delete(subjectOutcomes[index])
                            }
                            try? modelContext.save()
                        }
                    }
                    
                    Button(action: { showAddOutcome = true }) {
                        Label("Yeni Kazanım Ekle", systemImage: "plus.circle")
                    }
                }
            }
            .navigationTitle(subject.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
            .sheet(isPresented: $showAddTopic) {
                AddTopicSheet(subject: subject)
            }
            .sheet(isPresented: $showAddOutcome) {
                AddOutcomeSheet(subject: subject)
            }
            .sheet(item: $selectedTopic) { topic in
                TopicDetailView(topic: topic)
            }
        }
    }
}

struct StatBox: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.title.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Topic Row

struct TopicRow: View {
    let topic: TopicModel
    let questionCount: Int
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(topic.name)
                        .font(.body)
                    Text("\(questionCount) soru")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

struct OutcomeRow: View {
    let outcome: LearningOutcomeModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(outcome.code)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.blue)
            Text(outcome.description)
                .font(.body)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Topic Detail View

struct TopicDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let topic: TopicModel
    @Query private var questions: [QuestionModel]
    @Query private var outcomes: [LearningOutcomeModel]
    
    @State private var showAddOutcome = false
    
    private var topicQuestions: [QuestionModel] {
        questions.filter { $0.topics.contains { $0.id == topic.id } }
    }
    
    private var topicOutcomes: [LearningOutcomeModel] {
        outcomes.filter { $0.topic?.id == topic.id }
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section("Bilgi") {
                    HStack {
                        Text("Soru Sayısı")
                        Spacer()
                        Text("\(topicQuestions.count)")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Kazanımlar")
                        Spacer()
                        Text("\(topicOutcomes.count)")
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section("Bu Konudaki Sorular") {
                    if topicQuestions.isEmpty {
                        Text("Henüz soru eklenmemiş")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(topicQuestions.prefix(20)) { question in
                            HStack {
                                Text(question.questionText)
                                    .lineLimit(1)
                                Spacer()
                                if question.correctAnswerIndex != nil {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
                }
                
                Section("İlişkili Kazanımlar") {
                    ForEach(topicOutcomes) { outcome in
                        OutcomeRow(outcome: outcome)
                    }
                    
                    Button(action: { showAddOutcome = true }) {
                        Label("Kazanım Ekle", systemImage: "plus.circle")
                    }
                }
            }
            .navigationTitle(topic.name)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
            .sheet(isPresented: $showAddOutcome) {
                AddOutcomeSheet(subject: topic.subject, topic: topic)
            }
        }
    }
}

// MARK: - Add Sheets

struct AddSubjectSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var selectedType: Subject = .matematik
    @State private var colorHex = "#007AFF"
    
    let presetColors = ["#007AFF", "#34C759", "#FF9F0A", "#FF3B30", "#AF52DE", "#FF2D92", "#5AC8FA", "#30B0C7"]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Ders Bilgileri") {
                    TextField("Ders Adı (örn: 9. Sınıf Matematik)", text: $name)
                    
                    Picker("Tür", selection: $selectedType) {
                        ForEach(Subject.allCases) { s in
                            Label(s.rawValue, systemImage: s.icon).tag(s)
                        }
                    }
                }
                
                Section("Renk") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8)) {
                        ForEach(presetColors, id: \.self) { color in
                            Circle()
                                .fill(Color(hex: color))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary, lineWidth: colorHex == color ? 3 : 0)
                                )
                                .onTapGesture { colorHex = color }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Yeni Ders")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { save() }
                        .disabled(name.isEmpty)
                }
            }
        }
    }
    
    private func save() {
        let subject = SubjectModel(name: name, subjectType: selectedType, colorHex: colorHex)
        modelContext.insert(subject)
        try? modelContext.save()
        dismiss()
    }
}

struct AddTopicSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let subject: SubjectModel?
    let topic: TopicModel? // nil = yeni, dolu = düzenle
    
    @State private var name = ""
    @State private var order = 0
    
    init(subject: SubjectModel, topic: TopicModel? = nil) {
        self.subject = subject
        self.topic = topic
        if let topic = topic {
            _name = State(initialValue: topic.name)
            _order = State(initialValue: topic.order)
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Konu Bilgileri") {
                    TextField("Konu Adı (örn: Fonksiyonlar)", text: $name)
                    Stepper("Sıra: \(order)", value: $order, in: 0...100)
                }
            }
            .navigationTitle(topic == nil ? "Yeni Konu" : "Konuyu Düzenle")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { save() }
                        .disabled(name.isEmpty)
                }
            }
        }
    }
    
    private func save() {
        if let topic = topic {
            topic.name = name
            topic.order = order
        } else {
            let newTopic = TopicModel(name: name, order: order, subject: subject)
            modelContext.insert(newTopic)
        }
        try? modelContext.save()
        dismiss()
    }
}

struct AddOutcomeSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let subject: SubjectModel?
    let topic: TopicModel?
    
    @State private var code = ""
    @State private var description = ""
    @State private var order = 0
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Kazanım Bilgileri") {
                    TextField("Kod (örn: M.9.1.1)", text: $code)
                    TextField("Açıklama", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                    Stepper("Sıra: \(order)", value: $order, in: 0...100)
                }
                
                if let topic = topic {
                    Section {
                        Text("Bu kazanım şu konuya bağlanacak: \(topic.name)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Yeni Kazanım")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { save() }
                        .disabled(code.isEmpty || description.isEmpty)
                }
            }
        }
    }
    
    private func save() {
        let outcome = LearningOutcomeModel(
            code: code,
            description: description,
            order: order,
            subject: subject,
            topic: topic
        )
        modelContext.insert(outcome)
        try? modelContext.save()
        dismiss()
    }
}