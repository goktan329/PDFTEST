import Foundation
import SwiftData
import Combine
import PencilKit

// MARK: - Solve Session ViewModel

@MainActor
final class SolveSessionViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var session: SolveSessionModel?
    @Published var currentQuestion: QuestionModel?
    @Published var currentAttempt: UserAttemptModel?
    @Published var drawing: PKDrawing = PKDrawing()
    @Published var markedOptions: Set<Int> = [] // İşaretlenen şıklar (elimleme)
    @Published var selectedAnswerIndex: Int? // Kullanıcının cevabı
    @Published var showResult: Bool = false
    @Published var showAIExplanation: Bool = false
    @Published var aiExplanation: String = ""
    @Published var isGeneratingAI: Bool = false
    @Published var timeElapsed: Int = 0
    @Published var showQualityMark: Bool = false
    @Published var userSolutionNote: String = ""
    
    // Navigation
    @Published var canGoPrevious: Bool = false
    @Published var canGoNext: Bool = false
    
    // Stats
    @Published var currentStats: SessionStats = SessionStats()
    
    // MARK: - Private Properties
    
    private var modelContext: ModelContext?
    private var timer: Timer?
    private var questionStartTime: Date = Date()
    private var cancellables = Set<AnyCancellable>()
    
    // Services
    private let llmService = LLMService.shared
    
    struct SessionStats {
        var correct: Int = 0
        var wrong: Int = 0
        var blank: Int = 0
        var net: Double = 0.0
        var progress: Double = 0.0
        var currentQuestionNumber: Int = 0
        var totalQuestions: Int = 0
    }
    
    // MARK: - Initialization
    
    func configure(modelContext: ModelContext, session: SolveSessionModel) {
        self.modelContext = modelContext
        self.session = session
        loadCurrentQuestion()
        startTimer()
    }
    
    // MARK: - Question Loading
    
    private func loadCurrentQuestion() {
        guard let session = session,
              let modelContext = modelContext,
              session.currentQuestionIndex < session.questionIds.count else {
            finishSession()
            return
        }
        
        let questionId = session.questionIds[session.currentQuestionIndex]
        let descriptor = FetchDescriptor<QuestionModel>(predicate: #Predicate { $0.id == questionId })
        
        do {
            let questions = try modelContext.fetch(descriptor)
            currentQuestion = questions.first
            
            if let question = currentQuestion {
                // Mevcut attempt var mı kontrol et
                let attemptDescriptor = FetchDescriptor<UserAttemptModel>(
                    predicate: #Predicate { $0.question?.id == questionId && $0.session?.id == session.id }
                )
                let attempts = try modelContext.fetch(attemptDescriptor)
                currentAttempt = attempts.first
                
                if let attempt = currentAttempt {
                    // Mevcut deneme varsa durumu yükle
                    drawing = try? PKDrawing(data: attempt.drawingData ?? Data()) ?? PKDrawing()
                    markedOptions = Set(attempt.markedOptions)
                    selectedAnswerIndex = attempt.selectedAnswerIndex
                    userSolutionNote = question.userSolutionNote ?? ""
                    showQualityMark = question.isQualityMarked
                } else {
                    // Yeni attempt oluştur
                    resetForNewQuestion()
                }
                
                questionStartTime = Date()
                updateNavigationState()
                updateStats()
            }
        } catch {
            print("Soru yüklenemedi: \(error)")
        }
    }
    
    private func resetForNewQuestion() {
        drawing = PKDrawing()
        markedOptions = []
        selectedAnswerIndex = nil
        showResult = false
        showAIExplanation = false
        aiExplanation = ""
        userSolutionNote = ""
        showQualityMark = currentQuestion?.isQualityMarked ?? false
        
        // Yeni attempt oluştur
        let attemptNumber = (currentQuestion?.attempts.count ?? 0) + 1
        currentAttempt = UserAttemptModel(attemptNumber: attemptNumber)
        currentAttempt?.question = currentQuestion
        currentAttempt?.session = session
        if let attempt = currentAttempt {
            modelContext?.insert(attempt)
        }
    }
    
    // MARK: - Answer Handling
    
    func selectOption(_ index: Int) {
        guard selectedAnswerIndex == nil || selectedAnswerIndex == index else { return }
        selectedAnswerIndex = index
        markedOptions.remove(index) // Seçtiğinde elimleme işaretini kaldır
        evaluateAnswer()
    }
    
    func toggleOptionMark(_ index: Int) {
        if markedOptions.contains(index) {
            markedOptions.remove(index)
        } else {
            markedOptions.insert(index)
        }
        // Eğer bu şık seçiliyse seçimi kaldır
        if selectedAnswerIndex == index {
            selectedAnswerIndex = nil
            showResult = false
        }
        saveAttempt()
    }
    
    func clearSelection() {
        selectedAnswerIndex = nil
        showResult = false
        saveAttempt()
    }
    
    private func evaluateAnswer() {
        guard let question = currentQuestion,
              let attempt = currentAttempt,
              let selected = selectedAnswerIndex else { return }
        
        let correctIndex = question.correctAnswerIndex
        let status: AnswerStatus
        
        if let correct = correctIndex {
            if selected == correct {
                status = .correct
            } else {
                status = .wrong
            }
        } else {
            // Cevap anahtarı yoksa "Cevapsız" olarak bırak, kullanıcı sonradan kontrol etsin
            status = .unanswered
        }
        
        attempt.status = status
        attempt.selectedAnswerIndex = selected
        attempt.markedOptions = Array(markedOptions)
        attempt.timeSpentSeconds = Int(Date().timeIntervalSince(questionStartTime))
        attempt.drawingData = drawing.dataRepresentation()
        attempt.completedAt = Date()
        
        showResult = true
        saveAttempt()
        updateStats()
        
        // Yanlışsa wrong question bank'e ekle
        if status == .wrong || status == .blank {
            addToWrongQuestionBank(question: question, attempt: attempt)
        }
    }
    
    func markAsBlank() {
        guard let attempt = currentAttempt else { return }
        attempt.status = .blank
        attempt.selectedAnswerIndex = nil
        attempt.timeSpentSeconds = Int(Date().timeIntervalSince(questionStartTime))
        attempt.drawingData = drawing.dataRepresentation()
        attempt.completedAt = Date()
        
        showResult = true
        saveAttempt()
        updateStats()
        
        if let question = currentQuestion {
            addToWrongQuestionBank(question: question, attempt: attempt)
        }
    }
    
    // MARK: - Navigation
    
    func goToNextQuestion() {
        saveAttempt()
        guard let session = session else { return }
        
        if session.currentQuestionIndex < session.questionIds.count - 1 {
            session.currentQuestionIndex += 1
            loadCurrentQuestion()
        } else {
            finishSession()
        }
    }
    
    func goToPreviousQuestion() {
        saveAttempt()
        guard let session = session, session.currentQuestionIndex > 0 else { return }
        session.currentQuestionIndex -= 1
        loadCurrentQuestion()
    }
    
    func goToQuestion(at index: Int) {
        saveAttempt()
        guard let session = session, index >= 0, index < session.questionIds.count else { return }
        session.currentQuestionIndex = index
        loadCurrentQuestion()
    }
    
    private func updateNavigationState() {
        guard let session = session else { return }
        canGoPrevious = session.currentQuestionIndex > 0
        canGoNext = session.currentQuestionIndex < session.questionIds.count - 1
        
        currentStats.currentQuestionNumber = session.currentQuestionIndex + 1
        currentStats.totalQuestions = session.questionIds.count
        currentStats.progress = session.progress
    }
    
    // MARK: - Session Management
    
    private func finishSession() {
        stopTimer()
        guard let session = session else { return }
        
        session.isCompleted = true
        session.completedAt = Date()
        session.durationSeconds = Int(Date().timeIntervalSince(session.startedAt))
        session.recalculateStats()
        
        currentStats.correct = session.correctCount
        currentStats.wrong = session.wrongCount
        currentStats.blank = session.blankCount
        currentStats.net = session.netScore
        
        try? modelContext?.save()
    }
    
    func abandonSession() {
        stopTimer()
        // Session'ı silme, sadece durdur
    }
    
    // MARK: - Timer
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateTimer()
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func updateTimer() {
        timeElapsed = Int(Date().timeIntervalSince(questionStartTime))
        if let session = session {
            session.durationSeconds = Int(Date().timeIntervalSince(session.startedAt))
        }
    }
    
    // MARK: - Stats
    
    private func updateStats() {
        guard let session = session else { return }
        session.recalculateStats()
        
        currentStats.correct = session.correctCount
        currentStats.wrong = session.wrongCount
        currentStats.blank = session.blankCount
        currentStats.net = session.netScore
    }
    
    // MARK: - Wrong Question Bank
    
    private func addToWrongQuestionBank(question: QuestionModel, attempt: UserAttemptModel) {
        guard let modelContext = modelContext else { return }
        
        // Zaten varsa güncelle
        let descriptor = FetchDescriptor<WrongQuestionBankModel>(
            predicate: #Predicate { $0.question?.id == question.id }
        )
        
        do {
            let existing = try modelContext.fetch(descriptor)
            if let bankEntry = existing.first {
                bankEntry.wrongAttemptCount += 1
                bankEntry.lastWrongDate = Date()
                bankEntry.isResolved = false
            } else {
                let newEntry = WrongQuestionBankModel(question: question, firstWrongAttempt: attempt)
                modelContext.insert(newEntry)
            }
            try modelContext.save()
        } catch {
            print("Wrong question bank güncellenemedi: \(error)")
        }
    }
    
    // MARK: - Quality Questions
    
    func toggleQualityMark() {
        guard let question = currentQuestion else { return }
        question.isQualityMarked.toggle()
        showQualityMark = question.isQualityMarked
        question.updatedAt = Date()
        
        if question.isQualityMarked {
            // Quality questions'a ekle
            let qualityEntry = QualityQuestionModel(question: question, userRating: 5)
            modelContext?.insert(qualityEntry)
        } else {
            // Quality questions'dan kaldır
            let descriptor = FetchDescriptor<QualityQuestionModel>(
                predicate: #Predicate { $0.question?.id == question.id }
            )
            if let entries = try? modelContext?.fetch(descriptor) {
                for entry in entries {
                    modelContext?.delete(entry)
                }
            }
        }
        saveAttempt()
    }
    
    // MARK: - User Solution Note
    
    func saveSolutionNote(_ note: String) {
        currentQuestion?.userSolutionNote = note.isEmpty ? nil : note
        userSolutionNote = note
        saveAttempt()
    }
    
    // MARK: - AI Explanation
    
    func generateAIExplanation() async {
        guard let question = currentQuestion, !isGeneratingAI else { return }
        
        isGeneratingAI = true
        showAIExplanation = true
        aiExplanation = "Çözüm üretiliyor..."
        
        do {
            let request = LLMService.SolutionRequest(
                questionText: question.questionText,
                options: question.options.map { $0.text },
                correctAnswerIndex: question.correctAnswerIndex,
                subject: question.pdfSource?.subject ?? .matematik,
                userLanguage: "tr",
                includeStepByStep: true
            )
            
            let response = try await llmService.generateSolution(for: request)
            aiExplanation = formatAIResponse(response)
            question.aiSolution = response.explanation
            question.aiSolutionGeneratedAt = Date()
            try modelContext?.save()
        } catch {
            aiExplanation = "❌ Çözüm üretilemedi: \(error.localizedDescription)\n\nModel yüklü mü? Ayarlar > AI Model'den modeli indirip yükleyin."
        }
        
        isGeneratingAI = false
    }
    
    private func formatAIResponse(_ response: LLMService.SolutionResponse) -> String {
        var result = ""
        
        result += "## 🤖 AI Çözümü\n\n"
        result += response.explanation + "\n\n"
        
        if let steps = response.stepByStep, !steps.isEmpty {
            result += "### 📝 Adım Adım Çözüm\n"
            for (index, step) in steps.enumerated() {
                result += "\(index + 1). \(step)\n"
            }
            result += "\n"
        }
        
        if !response.keyConcepts.isEmpty {
            result += "### 🔑 Ana Kavramlar\n"
            result += response.keyConcepts.map { "• \($0)" }.joined(separator: "\n")
            result += "\n\n"
        }
        
        if let alternatives = response.alternativeMethods, !alternatives.isEmpty {
            result += "### 🔄 Alternatif Yöntemler\n"
            result += alternatives.map { "• \($0)" }.joined(separator: "\n")
            result += "\n\n"
        }
        
        result += "---\n"
        result += "*Model: \(response.modelUsed) • \(response.generatedAt.formatted(date: .omitted, time: .shortened))*"
        
        return result
    }
    
    // MARK: - Drawing
    
    func updateDrawing(_ newDrawing: PKDrawing) {
        drawing = newDrawing
        currentAttempt?.drawingData = newDrawing.dataRepresentation()
    }
    
    func clearDrawing() {
        drawing = PKDrawing()
        currentAttempt?.drawingData = nil
    }
    
    // MARK: - Persistence
    
    private func saveAttempt() {
        currentAttempt?.markedOptions = Array(markedOptions)
        currentAttempt?.selectedAnswerIndex = selectedAnswerIndex
        currentAttempt?.drawingData = drawing.dataRepresentation()
        currentAttempt?.timeSpentSeconds = Int(Date().timeIntervalSince(questionStartTime))
        try? modelContext?.save()
    }
    
    deinit {
        stopTimer()
    }
}

// MARK: - Session Creation Helper

extension SolveSessionViewModel {
    static func createSession(
        name: String,
        subject: Subject?,
        examCategory: ExamCategory,
        questionIds: [UUID],
        modelContext: ModelContext
    ) -> SolveSessionModel {
        let session = SolveSessionModel(
            name: name,
            subject: subject,
            examCategory: examCategory,
            questionIds: questionIds
        )
        modelContext.insert(session)
        try? modelContext.save()
        return session
    }
    
    static func createSessionFromWrongQuestions(
        subject: Subject?,
        modelContext: ModelContext,
        limit: Int = 20
    ) -> SolveSessionModel? {
        let descriptor = FetchDescriptor<WrongQuestionBankModel>(
            predicate: #Predicate { $0.isResolved == false },
            sortBy: [SortDescriptor(\.nextReviewDate ?? .distantFuture, order: .forward)]
        )
        
        guard let entries = try? modelContext.fetch(descriptor),
              !entries.isEmpty else { return nil }
        
        let questionIds = entries.prefix(limit).compactMap { $0.question?.id }
        guard !questionIds.isEmpty else { return nil }
        
        return createSession(
            name: "Yanlış/Boş Sorular Tekrarı",
            subject: subject,
            examCategory: .topicTest,
            questionIds: questionIds,
            modelContext: modelContext
        )
    }
    
    static func createSessionFromQualityQuestions(
        subject: Subject?,
        modelContext: ModelContext
    ) -> SolveSessionModel? {
        let descriptor = FetchDescriptor<QualityQuestionModel>(
            sortBy: [SortDescriptor(\.addedAt, order: .reverse)]
        )
        
        guard let entries = try? modelContext.fetch(descriptor),
              !entries.isEmpty else { return nil }
        
        let questionIds = entries.compactMap { $0.question?.id }
        guard !questionIds.isEmpty else { return nil }
        
        return createSession(
            name: "Kaliteli Sorular Arşivi",
            subject: subject,
            examCategory: .topicTest,
            questionIds: questionIds,
            modelContext: modelContext
        )
    }
}