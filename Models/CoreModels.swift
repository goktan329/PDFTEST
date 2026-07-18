import Foundation
import SwiftData
import CoreGraphics

// MARK: - Enums

enum QuestionType: String, Codable, CaseIterable {
    case multipleChoice = "Çoktan Seçmeli"
    case shortAnswer = "Klasik"
    case trueFalse = "Doğru/Yanlış"
    case matching = "Eşleştirme"
}

enum Subject: String, Codable, CaseIterable, Identifiable {
    case turkce = "Türkçe"
    case matematik = "Matematik"
    case fen = "Fen Bilimleri"
    case sosyal = "Sosyal Bilgiler"
    case din = "Din Kültürü"
    case ingilizce = "İngilizce"
    case diger = "Diğer"
    
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .turkce: return "textformat"
        case .matematik: return "function"
        case .fen: return "atom"
        case .sosyal: return "globe.europe.africa"
        case .din: return "book.closed"
        case .ingilizce: return "character.bubble"
        case .diger: return "questionmark.circle"
        }
    }
}

enum ExamCategory: String, Codable, CaseIterable, Identifiable {
    case topicTest = "Konu Testi"
    case deneme = "Deneme Sınavı"
    case yks = "YKS / AYT / TYT"
    case lgs = "LGS"
    case other = "Diğer"
    
    var id: String { rawValue }
}

enum AnswerStatus: String, Codable, CaseIterable {
    case correct = "Doğru"
    case wrong = "Yanlış"
    case blank = "Boş"
    case unanswered = "Cevapsız"
}

enum Difficulty: Int, Codable, CaseIterable, Comparable {
    case easy = 1
    case medium = 2
    case hard = 3
    
    static func < (lhs: Difficulty, rhs: Difficulty) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - SwiftData Models

@Model
final class SubjectModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var subjectType: Subject
    var colorHex: String
    var order: Int
    var createdAt: Date
    
    @Relationship(deleteRule: .cascade, inverse: \TopicModel.subject)
    var topics: [TopicModel] = []
    
    @Relationship(deleteRule: .cascade, inverse: \LearningOutcomeModel.subject)
    var learningOutcomes: [LearningOutcomeModel] = []
    
    init(name: String, subjectType: Subject, colorHex: String = "#007AFF", order: Int = 0) {
        self.id = UUID()
        self.name = name
        self.subjectType = subjectType
        self.colorHex = colorHex
        self.order = order
        self.createdAt = Date()
    }
}

@Model
final class TopicModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var order: Int
    var createdAt: Date
    
    var subject: SubjectModel?
    
    @Relationship(deleteRule: .cascade, inverse: \QuestionModel.topics)
    var questions: [QuestionModel] = []
    
    @Relationship(deleteRule: .cascade, inverse: \LearningOutcomeModel.topic)
    var learningOutcomes: [LearningOutcomeModel] = []
    
    init(name: String, order: Int = 0, subject: SubjectModel? = nil) {
        self.id = UUID()
        self.name = name
        self.order = order
        self.createdAt = Date()
        self.subject = subject
    }
}

@Model
final class LearningOutcomeModel {
    @Attribute(.unique) var id: UUID
    var code: String // Örn: "M.9.1.1"
    var description: String
    var order: Int
    var createdAt: Date
    
    var subject: SubjectModel?
    var topic: TopicModel?
    
    @Relationship(deleteRule: .cascade, inverse: \QuestionModel.learningOutcomes)
    var questions: [QuestionModel] = []
    
    init(code: String, description: String, order: Int = 0, subject: SubjectModel? = nil, topic: TopicModel? = nil) {
        self.id = UUID()
        self.code = code
        self.description = description
        self.order = order
        self.createdAt = Date()
        self.subject = subject
        self.topic = topic
    }
    
    var displayName: String { "\(code) - \(description)" }
}

@Model
final class PDFSourceModel {
    @Attribute(.unique) var id: UUID
    var fileName: String
    var filePath: String // Sandbox içindeki yol
    var fileSize: Int64
    var pageCount: Int
    var subject: Subject?
    var examCategory: ExamCategory
    var importedAt: Date
    var parsingStatus: ParsingStatus
    var parsingError: String?
    var totalQuestionsFound: Int
    var successfullyParsed: Int
    
    @Relationship(deleteRule: .cascade, inverse: \QuestionModel.pdfSource)
    var questions: [QuestionModel] = []
    
    init(fileName: String, filePath: String, fileSize: Int64, pageCount: Int, subject: Subject? = nil, examCategory: ExamCategory = .topicTest) {
        self.id = UUID()
        self.fileName = fileName
        self.filePath = filePath
        self.fileSize = fileSize
        self.pageCount = pageCount
        self.subject = subject
        self.examCategory = examCategory
        self.importedAt = Date()
        self.parsingStatus = .pending
        self.totalQuestionsFound = 0
        self.successfullyParsed = 0
    }
}

enum ParsingStatus: String, Codable, CaseIterable {
    case pending = "Bekliyor"
    case processing = "İşleniyor"
    case completed = "Tamamlandı"
    case partial = "Kısmi Başarı"
    case failed = "Başarısız"
    case needsReview = "Gözden Geçir"
}

@Model
final class QuestionModel {
    @Attribute(.unique) var id: UUID
    var questionText: String
    var questionImageData: Data? // Soru görseli (opsiyonel)
    var questionType: QuestionType
    var options: [OptionModel] // A, B, C, D, E
    var correctAnswerIndex: Int? // 0-4 arası, nil ise cevap bulunamadı
    var explanation: String? // Resmi çözüm/aciklama
    var userSolutionNote: String? // Kullanıcının kendi çözüm notu
    var aiSolution: String? // AI tarafından üretilen çözüm
    var aiSolutionGeneratedAt: Date?
    
    var difficulty: Difficulty
    var estimatedTimeSeconds: Int // Tahmini çözme süresi
    var tags: [String] // Etiketler
    var isQualityMarked: Bool // Kaliteli soru işareti
    
    var createdAt: Date
    var updatedAt: Date
    var parsedAt: Date?
    var parsingConfidence: Double // 0.0 - 1.0
    
    var pdfSource: PDFSourceModel?
    
    @Relationship(deleteRule: .nullify, inverse: \TopicModel.questions)
    var topics: [TopicModel] = []
    
    @Relationship(deleteRule: .nullify, inverse: \LearningOutcomeModel.questions)
    var learningOutcomes: [LearningOutcomeModel] = []
    
    @Relationship(deleteRule: .cascade, inverse: \UserAttemptModel.question)
    var attempts: [UserAttemptModel] = []
    
    init(
        questionText: String,
        questionType: QuestionType = .multipleChoice,
        options: [OptionModel] = [],
        correctAnswerIndex: Int? = nil,
        explanation: String? = nil,
        difficulty: Difficulty = .medium,
        estimatedTimeSeconds: Int = 90,
        tags: [String] = [],
        pdfSource: PDFSourceModel? = nil,
        parsingConfidence: Double = 0.0
    ) {
        self.id = UUID()
        self.questionText = questionText
        self.questionType = questionType
        self.options = options
        self.correctAnswerIndex = correctAnswerIndex
        self.explanation = explanation
        self.difficulty = difficulty
        self.estimatedTimeSeconds = estimatedTimeSeconds
        self.tags = tags
        self.isQualityMarked = false
        self.createdAt = Date()
        self.updatedAt = Date()
        self.parsingConfidence = parsingConfidence
        self.pdfSource = pdfSource
    }
    
    var correctOption: OptionModel? {
        guard let idx = correctAnswerIndex, idx < options.count else { return nil }
        return options[idx]
    }
    
    var optionLetters: [String] {
        ["A", "B", "C", "D", "E"].prefix(options.count).map { String($0) }
    }
}

@Model
final class OptionModel {
    @Attribute(.unique) var id: UUID
    var text: String
    var imageData: Data? // Şık görseli (opsiyonel)
    var order: Int
    var question: QuestionModel?
    
    init(text: String, order: Int, imageData: Data? = nil) {
        self.id = UUID()
        self.text = text
        self.order = order
        self.imageData = imageData
    }
}

@Model
final class UserAttemptModel {
    @Attribute(.unique) var id: UUID
    var selectedAnswerIndex: Int? // Kullanıcının işaretlediği şık
    var status: AnswerStatus
    var isMarkedForReview: Boolean // Bayrak işareti
    var timeSpentSeconds: Int
    var drawingData: Data? // PencilKit çizim verisi (PKDrawing.dataRepresentation())
    var markedOptions: [Int] // İşaretlenen şıklar (elimleme için)
    var startedAt: Date
    var completedAt: Date?
    var attemptNumber: Int // Bu soru için kaçıncı deneme
    
    var question: QuestionModel?
    var session: SolveSessionModel?
    
    init(
        selectedAnswerIndex: Int? = nil,
        status: AnswerStatus = .unanswered,
        timeSpentSeconds: Int = 0,
        drawingData: Data? = nil,
        markedOptions: [Int] = [],
        attemptNumber: Int = 1
    ) {
        self.id = UUID()
        self.selectedAnswerIndex = selectedAnswerIndex
        self.status = status
        self.isMarkedForReview = false
        self.timeSpentSeconds = timeSpentSeconds
        self.drawingData = drawingData
        self.markedOptions = markedOptions
        self.startedAt = Date()
        self.attemptNumber = attemptNumber
    }
    
    var isCorrect: Bool { status == .correct }
    var isWrong: Bool { status == .wrong }
    var isBlank: Bool { status == .blank }
}

@Model
final class SolveSessionModel {
    @Attribute(.unique) var id: UUID
    var name: String // "Matematik Deneme 1", "Fen Konu Testi" vb.
    var subject: Subject?
    var examCategory: ExamCategory
    var questionIds: [UUID] // Bu oturumdaki soruların ID'leri (sıralı)
    var currentQuestionIndex: Int
    var totalQuestions: Int
    var correctCount: Int
    var wrongCount: Int
    var blankCount: Int
    var netScore: Double // 4 yanlış = 1 doğru gider
    var startedAt: Date
    var completedAt: Date?
    var durationSeconds: Int
    var isCompleted: Bool
    
    @Relationship(deleteRule: .cascade, inverse: \UserAttemptModel.session)
    var attempts: [UserAttemptModel] = []
    
    init(name: String, subject: Subject? = nil, examCategory: ExamCategory = .topicTest, questionIds: [UUID] = []) {
        self.id = UUID()
        self.name = name
        self.subject = subject
        self.examCategory = examCategory
        self.questionIds = questionIds
        self.currentQuestionIndex = 0
        self.totalQuestions = questionIds.count
        self.correctCount = 0
        self.wrongCount = 0
        self.blankCount = 0
        self.netScore = 0.0
        self.startedAt = Date()
        self.durationSeconds = 0
        self.isCompleted = false
    }
    
    var currentQuestionId: UUID? {
        guard currentQuestionIndex < questionIds.count else { return nil }
        return questionIds[currentQuestionIndex]
    }
    
    var progress: Double {
        guard totalQuestions > 0 else { return 0 }
        return Double(currentQuestionIndex) / Double(totalQuestions)
    }
    
    func recalculateStats() {
        correctCount = attempts.filter { $0.status == .correct }.count
        wrongCount = attempts.filter { $0.status == .wrong }.count
        blankCount = attempts.filter { $0.status == .blank }.count
        netScore = Double(correctCount) - Double(wrongCount) / 4.0
    }
}

@Model
final class WrongQuestionBankModel {
    @Attribute(.unique) var id: UUID
    var question: QuestionModel?
    var firstWrongAttempt: UserAttemptModel?
    var wrongAttemptCount: Int
    var lastWrongDate: Date
    var isResolved: Bool // Doğru çözüldü mü?
    var resolvedAt: Date?
    var resolvedAttempt: UserAttemptModel?
    var reviewCount: Int // Kaç kez tekrar çözüldü
    var nextReviewDate: Date? // Spaced repetition için
    
    init(question: QuestionModel, firstWrongAttempt: UserAttemptModel) {
        self.id = UUID()
        self.question = question
        self.firstWrongAttempt = firstWrongAttempt
        self.wrongAttemptCount = 1
        self.lastWrongDate = Date()
        self.isResolved = false
        self.reviewCount = 0
        self.nextReviewDate = Calendar.current.date(byAdding: .day, value: 1, to: Date())
    }
}

@Model
final class QualityQuestionModel {
    @Attribute(.unique) var id: UUID
    var question: QuestionModel?
    var addedAt: Date
    var userRating: Int // 1-5 arası kullanıcı puanı
    var userTags: [String]
    var note: String?
    
    init(question: QuestionModel, userRating: Int = 5, userTags: [String] = [], note: String? = nil) {
        self.id = UUID()
        self.question = question
        self.addedAt = Date()
        self.userRating = userRating
        self.userTags = userTags
        self.note = note
    }
}

// MARK: - Codable Versions (for import/export, backup)

struct QuestionExport: Codable {
    let id: UUID
    let questionText: String
    let questionType: QuestionType
    let options: [OptionExport]
    let correctAnswerIndex: Int?
    let explanation: String?
    let difficulty: Difficulty
    let estimatedTimeSeconds: Int
    let tags: [String]
    let learningOutcomeCodes: [String]
    let topicNames: [String]
    let subjectName: String
}

struct OptionExport: Codable {
    let text: String
    let order: Int
}

struct LearningOutcomeExport: Codable {
    let code: String
    let description: String
    let subjectName: String
    let topicName: String?
}

struct TopicExport: Codable {
    let name: String
    let subjectName: String
    let learningOutcomes: [LearningOutcomeExport]
}