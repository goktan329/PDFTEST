import Foundation
import PDFKit
import Vision
import CoreGraphics
import UniformTypeIdentifiers

// MARK: - PDF Parser Service (On-Device)

/// PDF'lerden soru/çıkarma servisi - Tamamen cihazda çalışır
/// Not: Karmaşık PDF layout'larda %100 doğruluk imkansız, manuel düzeltme akışı şart
@MainActor
final class PDFParserService: ObservableObject {
    static let shared = PDFParserService()
    
    @Published var parsingProgress: Double = 0.0
    @Published var currentStatus: String = ""
    @Published var isParsing: Bool = false
    
    private init() {}
    
    // MARK: - Public API
    
    /// PDF dosyasını parse et ve soruları çıkar
    func parsePDF(
        at url: URL,
        subject: Subject? = nil,
        examCategory: ExamCategory = .topicTest,
        progressHandler: @escaping (Double, String) -> Void = { _, _ in }
    ) async throws -> ParsedPDFResult {
        
        isParsing = true
        parsingProgress = 0.0
        currentStatus = "PDF açılıyor..."
        progressHandler(0.0, currentStatus)
        
        defer {
            isParsing = false
            parsingProgress = 1.0
            currentStatus = "Tamamlandı"
            progressHandler(1.0, currentStatus)
        }
        
        guard let document = PDFDocument(url: url) else {
            throw PDFParserError.cannotOpenDocument
        }
        
        let pageCount = document.pageCount
        currentStatus = "\(pageCount) sayfa taranıyor..."
        progressHandler(0.1, currentStatus)
        
        // 1. Tüm sayfalardan metin ve görsel çıkar
        var pagesContent: [PageContent] = []
        
        for pageIndex in 0..<pageCount {
            let progress = 0.1 + (0.4 * Double(pageIndex) / Double(max(1, pageCount)))
            currentStatus = "Sayfa \(pageIndex + 1)/\(pageCount) işleniyor..."
            progressHandler(progress, currentStatus)
            
            guard let page = document.page(at: pageIndex) else { continue }
            let content = try await extractPageContent(page: page, pageIndex: pageIndex)
            pagesContent.append(content)
        }
        
        currentStatus = "Soru blokları tespit ediliyor..."
        progressHandler(0.5, currentStatus)
        
        // 2. Sayfa içeriklerinden soru bloklarını ayır
        let questionBlocks = try detectQuestionBlocks(from: pagesContent)
        
        currentStatus = "\(questionBlocks.count) soru bloğu bulundu, seçenekler ayrıştırılıyor..."
        progressHandler(0.6, currentStatus)
        
        // 3. Her bloğu soru + şıklara ayır
        var parsedQuestions: [ParsedQuestion] = []
        
        for (index, block) in questionBlocks.enumerated() {
            let progress = 0.6 + (0.35 * Double(index) / Double(max(1, questionBlocks.count)))
            currentStatus = "Soru \(index + 1)/\(questionBlocks.count) ayrıştırılıyor..."
            progressHandler(progress, currentStatus)
            
            if let question = try parseQuestionBlock(block, globalIndex: index) {
                parsedQuestions.append(question)
            }
        }
        
        currentStatus = "Cevap anahtarı aranıyor..."
        progressHandler(0.95, currentStatus)
        
        // 4. Cevap anahtarı sayfasını bul ve eşleştir
        let answerKey = try findAndParseAnswerKey(from: pagesContent)
        applyAnswerKey(answerKey, to: &parsedQuestions)
        
        currentStatus = "Tamamlandı: \(parsedQuestions.count) soru çıkarıldı"
        progressHandler(1.0, currentStatus)
        
        return ParsedPDFResult(
            sourceURL: url,
            fileName: url.lastPathComponent,
            pageCount: pageCount,
            subject: subject,
            examCategory: examCategory,
            questions: parsedQuestions,
            answerKey: answerKey,
            parsingWarnings: generateWarnings(questions: parsedQuestions, answerKey: answerKey)
        )
    }
    
    // MARK: - Page Content Extraction
    
    private struct PageContent {
        let pageIndex: Int
        let text: String
        let attributedText: NSAttributedString?
        let bounds: CGRect
        let images: [PDFImageInfo]
        let textBlocks: [TextBlock]
    }
    
    private struct PDFImageInfo {
        let image: CGImage
        let bounds: CGRect
        let pageIndex: Int
    }
    
    private struct TextBlock {
        let text: String
        let bounds: CGRect
        let fontSize: CGFloat
        let fontName: String
        let isBold: Bool
        let pageIndex: Int
    }
    
    private func extractPageContent(page: PDFPage, pageIndex: Int) async throws -> PageContent {
        // Metin çıkarma
        let text = page.string ?? ""
        let attributedText = page.attributedString
        
        // Görselleri çıkar
        var images: [PDFImageInfo] = []
        if let pageRef = page.pageRef {
            let renderer = UIGraphicsImageRenderer(bounds: page.bounds(for: .mediaBox))
            let image = renderer.image { ctx in
                UIColor.white.setFill()
                ctx.fill(page.bounds(for: .mediaBox))
                ctx.cgContext.translateBy(x: 0, y: page.bounds(for: .mediaBox).height)
                ctx.cgContext.scaleBy(x: 1, y: -1)
                ctx.cgContext.drawPDFPage(pageRef)
            }
            if let cgImage = image.cgImage {
                images.append(PDFImageInfo(image: cgImage, bounds: page.bounds(for: .mediaBox), pageIndex: pageIndex))
            }
        }
        
        // Text block'ları çıkar (font bilgileri ile)
        let textBlocks = extractTextBlocks(from: page, pageIndex: pageIndex)
        
        return PageContent(
            pageIndex: pageIndex,
            text: text,
            attributedText: attributedText,
            bounds: page.bounds(for: .mediaBox),
            images: images,
            textBlocks: textBlocks
        )
    }
    
    private func extractTextBlocks(from page: PDFPage, pageIndex: Int) -> [TextBlock] {
        var blocks: [TextBlock] = []
        
        guard let attributedString = page.attributedString else { return blocks }
        
        attributedString.enumerateAttribute(.font, in: NSRange(location: 0, length: attributedString.length), options: []) { value, range, _ in
            if let font = value as? UIFont {
                let text = (attributedString.string as NSString).substring(with: range)
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                
                // Bounds tahmini (PDFKit tam bounds vermez, yaklaşık)
                let bounds = CGRect(x: 0, y: 0, width: 100, height: font.pointSize)
                
                let isBold = font.fontDescriptor.symbolicTraits.contains(.traitBold)
                
                blocks.append(TextBlock(
                    text: trimmed,
                    bounds: bounds,
                    fontSize: font.pointSize,
                    fontName: font.fontName,
                    isBold: isBold,
                    pageIndex: pageIndex
                ))
            }
        }
        
        return blocks
    }
    
    // MARK: - Question Block Detection
    
    private struct RawQuestionBlock {
        let pageIndex: Int
        let textBlocks: [TextBlock]
        let images: [PDFImageInfo]
        let combinedText: String
        let bounds: CGRect
        var suspectedQuestionNumber: Int?
        var suspectedAnswerIndex: Int?
    }
    
    private func detectQuestionBlocks(from pagesContent: [PageContent]) throws -> [RawQuestionBlock] {
        var allBlocks: [RawQuestionBlock] = []
        
        for pageContent in pagesContent {
            let pageBlocks = detectBlocksOnPage(pageContent)
            allBlocks.append(contentsOf: pageBlocks)
        }
        
        // Soru numaralarına göre sırala ve filtrele
        allBlocks.sort { ($0.suspectedQuestionNumber ?? Int.max) < ($1.suspectedQuestionNumber ?? Int.max) }
        
        // Çok küçük/geçersiz blokları filtrele
        return allBlocks.filter { block in
            block.combinedText.count > 20 && block.suspectedQuestionNumber != nil
        }
    }
    
    private func detectBlocksOnPage(_ pageContent: PageContent) -> [RawQuestionBlock] {
        var blocks: [RawQuestionBlock] = []
        var currentBlockTextBlocks: [TextBlock] = []
        var currentBlockImages: [PDFImageInfo] = []
        var currentQuestionNumber: Int?
        
        let sortedBlocks = pageContent.textBlocks.sorted { $0.bounds.minY < $1.bounds.minY }
        
        for textBlock in sortedBlocks {
            // Soru numarası pattern'i ara: "1.", "1)", "Soru 1", "Q1" vb.
            let questionNumber = extractQuestionNumber(from: textBlock.text)
            
            if let qNum = questionNumber {
                // Önceki bloğu kaydet
                if !currentBlockTextBlocks.isEmpty, let prevNum = currentQuestionNumber {
                    let combined = currentBlockTextBlocks.map { $0.text }.joined(separator: "\n")
                    let bounds = calculateBounds(currentBlockTextBlocks)
                    blocks.append(RawQuestionBlock(
                        pageIndex: pageContent.pageIndex,
                        textBlocks: currentBlockTextBlocks,
                        images: currentBlockImages,
                        combinedText: combined,
                        bounds: bounds,
                        suspectedQuestionNumber: prevNum
                    ))
                }
                
                // Yeni blok başlat
                currentQuestionNumber = qNum
                currentBlockTextBlocks = [textBlock]
                currentBlockImages = pageContent.images.filter { intersects($0.bounds, calculateBounds([textBlock])) }
            } else {
                // Mevcut bloğa ekle
                currentBlockTextBlocks.append(textBlock)
            }
        }
        
        // Son bloğu ekle
        if !currentBlockTextBlocks.isEmpty, let qNum = currentQuestionNumber {
            let combined = currentBlockTextBlocks.map { $0.text }.joined(separator: "\n")
            let bounds = calculateBounds(currentBlockTextBlocks)
            blocks.append(RawQuestionBlock(
                pageIndex: pageContent.pageIndex,
                textBlocks: currentBlockTextBlocks,
                images: currentBlockImages,
                combinedText: combined,
                bounds: bounds,
                suspectedQuestionNumber: qNum
            ))
        }
        
        return blocks
    }
    
    private func extractQuestionNumber(from text: String) -> Int? {
        let patterns = [
            #"^\s*(\d{1,3})[\.\)]\s"#,  // "1. " veya "1) "
            #"^\s*Soru\s+(\d{1,3})"#,    // "Soru 1"
            #"^\s*Q(\d{1,3})"#,          // "Q1"
            #"^\s*(\d{1,3})\s*[\.\-]"#   // "1 -"
        ]
        
        for pattern in patterns {
            let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            let range = NSRange(location: 0, length: text.utf16.count)
            if let match = regex?.firstMatch(in: text, options: [], range: range),
               let range2 = Range(match.range(at: 1), in: text),
               let num = Int(text[range2]) {
                return num
            }
        }
        return nil
    }
    
    private func calculateBounds(_ blocks: [TextBlock]) -> CGRect {
        guard !blocks.isEmpty else { return .zero }
        let minX = blocks.map { $0.bounds.minX }.min() ?? 0
        let minY = blocks.map { $0.bounds.minY }.min() ?? 0
        let maxX = blocks.map { $0.bounds.maxX }.max() ?? 0
        let maxY = blocks.map { $0.bounds.maxY }.max() ?? 0
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
    
    private func intersects(_ bounds1: CGRect, _ bounds2: CGRect) -> Bool {
        return bounds1.intersects(bounds2)
    }
    
    // MARK: - Question Block Parsing
    
    struct ParsedQuestion {
        let globalIndex: Int
        let questionText: String
        let options: [ParsedOption]
        let correctAnswerIndex: Int?
        let explanation: String?
        let questionType: QuestionType
        let confidence: Double
        let sourcePageIndex: Int
        let sourceBounds: CGRect
        let images: [PDFImageInfo]
    }
    
    struct ParsedOption {
        let letter: String // "A", "B", "C", "D", "E"
        let text: String
        let imageData: Data?
        let bounds: CGRect
    }
    
    private func parseQuestionBlock(_ block: RawQuestionBlock, globalIndex: Int) throws -> ParsedQuestion? {
        let text = block.combinedText
        
        // Şık pattern'leri: "A) ", "A- ", "A. ", "A )" vb.
        let optionPattern = #"([A-E])[\.\)\-\s]\s*(.+?)(?=\s*[A-E][\.\)\-\s]|$)"#
        let regex = try NSRegularExpression(pattern: optionPattern, options: [.dotMatchesLineSeparators])
        let range = NSRange(location: 0, length: text.utf16.count)
        
        var options: [ParsedOption] = []
        var lastMatchEnd = 0
        var questionTextParts: [String] = []
        
        let matches = regex.matches(in: text, options: [], range: range)
        
        for match in matches {
            let matchRange = Range(match.range, in: text)!
            let beforeMatch = String(text[text.index(text.startIndex, offsetBy: lastMatchEnd)..<matchRange.lowerBound])
            
            if options.isEmpty {
                // İlk şıktan önceki kısım soru metnidir
                questionTextParts.append(beforeMatch.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            
            if let letterRange = Range(match.range(at: 1), in: text),
               let textRange = Range(match.range(at: 2), in: text) {
                let letter = String(text[letterRange]).uppercased()
                let optionText = String(text[textRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                
                options.append(ParsedOption(
                    letter: letter,
                    text: optionText,
                    imageData: nil,
                    bounds: .zero
                ))
            }
            
            lastMatchEnd = match.range.upperBound
        }
        
        // Son şıktan sonrası
        if lastMatchEnd < text.utf16.count {
            let afterLast = String(text[text.index(text.startIndex, offsetBy: lastMatchEnd)...])
            if !options.isEmpty {
                // Son şığa ekle (açıklama olabilir)
                if var lastOption = options.popLast() {
                    lastOption = ParsedOption(
                        letter: lastOption.letter,
                        text: lastOption.text + "\n" + afterLast.trimmingCharacters(in: .whitespacesAndNewlines),
                        imageData: lastOption.imageData,
                        bounds: lastOption.bounds
                    )
                    options.append(lastOption)
                }
            }
        }
        
        let questionText = questionTextParts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        
        // En az 2 şık ve soru metni olmalı
        guard options.count >= 2, !questionText.isEmpty else {
            return nil
        }
        
        // Şıkları A-B-C-D-E sırasına göre sırala
        let orderedOptions = options.sorted { optionOrder($0.letter) < optionOrder($1.letter) }
        
        // Cevap anahtarı henüz yok, sonra eşleştirilecek
        let confidence = calculateConfidence(questionText: questionText, options: orderedOptions)
        
        return ParsedQuestion(
            globalIndex: globalIndex,
            questionText: questionText,
            options: orderedOptions,
            correctAnswerIndex: nil,
            explanation: nil,
            questionType: .multipleChoice,
            confidence: confidence,
            sourcePageIndex: block.pageIndex,
            sourceBounds: block.bounds,
            images: block.images
        )
    }
    
    private func optionOrder(_ letter: String) -> Int {
        ["A", "B", "C", "D", "E"].firstIndex(of: letter.uppercased()) ?? 99
    }
    
    private func calculateConfidence(questionText: String, options: [ParsedOption]) -> Double {
        var score = 0.0
        
        // Soru metni uzunluğu
        if questionText.count > 30 { score += 0.2 }
        else if questionText.count > 10 { score += 0.1 }
        
        // Şık sayısı
        if options.count == 5 { score += 0.3 }
        else if options.count == 4 { score += 0.25 }
        else if options.count >= 2 { score += 0.15 }
        
        // Şık uzunlukları dengeli mi?
        let lengths = options.map { $0.text.count }
        let avgLen = Double(lengths.reduce(0, +)) / Double(lengths.count)
        let variance = lengths.map { pow(Double($0) - avgLen, 2) }.reduce(0, +) / Double(lengths.count)
        if variance < avgLen * 0.5 { score += 0.2 } // Dengeli
        
        // Soru işareti var mı?
        if questionText.contains("?") || questionText.contains("soru") || questionText.contains("bulunuz") || questionText.contains("hesaplayınız") {
            score += 0.15
        }
        
        return min(score, 1.0)
    }
    
    // MARK: - Answer Key Detection
    
    struct AnswerKey {
        let answers: [Int: Int] // questionNumber -> optionIndex (0-based)
        let sourcePageIndex: Int
        let confidence: Double
    }
    
    private func findAndParseAnswerKey(from pagesContent: [PageContent]) throws -> AnswerKey? {
        // Cevap anahtarı genellikle son sayfalarda, "CEVAP ANAHTARI", "CEVAPLAR", "ANSWER KEY" gibi başlıklarla olur
        let keyPatterns = [
            "cevap anahtar", "cevaplar", "answer key", "cevap ka",
            "doğru cevap", "cevap:", "key:"
        ]
        
        for pageContent in pagesContent.reversed() { // Sondan başa
            let text = pageContent.text.lowercased()
            
            for pattern in keyPatterns {
                if text.contains(pattern) {
                    // Bu sayfa cevap anahtarı olabilir
                    return try parseAnswerKeyPage(pageContent)
                }
            }
        }
        
        return nil
    }
    
    private func parseAnswerKeyPage(_ pageContent: PageContent) throws -> AnswerKey {
        let text = pageContent.text
        var answers: [Int: Int] = [:]
        
        // Pattern: "1 A", "1. A", "1) A", "1 - A", "Soru 1: A" vb.
        let patterns = [
            #"(\d{1,3})[\.\)\-\s]\s*([A-E])"#,
            #"Soru\s+(\d{1,3})\s*[:]\s*([A-E])"#,
            #"(\d{1,3})\s+([A-E])\b"#
        ]
        
        for pattern in patterns {
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            let range = NSRange(location: 0, length: text.utf16.count)
            let matches = regex.matches(in: text, options: [], range: range)
            
            for match in matches {
                if let qRange = Range(match.range(at: 1), in: text),
                   let aRange = Range(match.range(at: 2), in: text),
                   let qNum = Int(text[qRange]),
                   let optIndex = optionIndex(String(text[aRange])) {
                    answers[qNum] = optIndex
                }
            }
            
            if !answers.isEmpty { break }
        }
        
        let confidence = answers.isEmpty ? 0.0 : min(Double(answers.count) / 20.0, 1.0)
        
        return AnswerKey(
            answers: answers,
            sourcePageIndex: pageContent.pageIndex,
            confidence: confidence
        )
    }
    
    private func optionIndex(_ letter: String) -> Int? {
        ["A", "B", "C", "D", "E"].firstIndex(of: letter.uppercased())
    }
    
    private func applyAnswerKey(_ answerKey: AnswerKey?, to questions: inout [ParsedQuestion]) {
        guard let answerKey = answerKey else { return }
        
        for (index, question) in questions.enumerated() {
            let qNum = index + 1 // Global index 0-based, soru numarası 1-based
            if let answerIndex = answerKey.answers[qNum] {
                // Bu sorunun şıklarında bu harf var mı?
                if answerIndex < question.options.count {
                    var updatedQuestion = question
                    // CorrectAnswerIndex güncelle - immutable struct olduğu için yeni oluştur
                    questions[index] = ParsedQuestion(
                        globalIndex: question.globalIndex,
                        questionText: question.questionText,
                        options: question.options,
                        correctAnswerIndex: answerIndex,
                        explanation: question.explanation,
                        questionType: question.questionType,
                        confidence: min(question.confidence + 0.2, 1.0),
                        sourcePageIndex: question.sourcePageIndex,
                        sourceBounds: question.sourceBounds,
                        images: question.images
                    )
                }
            }
        }
    }
    
    // MARK: - Result & Warnings
    
    struct ParsedPDFResult {
        let sourceURL: URL
        let fileName: String
        let pageCount: Int
        let subject: Subject?
        let examCategory: ExamCategory
        let questions: [ParsedQuestion]
        let answerKey: AnswerKey?
        let parsingWarnings: [String]
    }
    
    private func generateWarnings(questions: [ParsedQuestion], answerKey: AnswerKey?) -> [String] {
        var warnings: [String] = []
        
        let lowConfidence = questions.filter { $0.confidence < 0.5 }.count
        if lowConfidence > 0 {
            warnings.append("\(lowConfidence) soru düşük güvenilirlikle çıkarıldı, manuel kontrol önerilir")
        }
        
        let noAnswer = questions.filter { $0.correctAnswerIndex == nil }.count
        if noAnswer > 0 {
            warnings.append("\(noAnswer) sorunun cevabı bulunamadı (cevap anahtarı eşleşmedi)")
        }
        
        let fewOptions = questions.filter { $0.options.count < 4 }.count
        if fewOptions > 0 {
            warnings.append("\(fewOptions) soruda 4'ten az şık tespit edildi")
        }
        
        if answerKey == nil {
            warnings.append("Cevap anahtarı sayfası tespit edilemedi, cevaplar manuel girilmeli")
        } else if answerKey!.confidence < 0.7 {
            warnings.append("Cevap anahtarı düşük güvenilirlikle okundu, kontrol edin")
        }
        
        if questions.count < 5 {
            warnings.append("Çok az soru (\(questions.count)) çıkarıldı, PDF formatı uygun olmayabilir")
        }
        
        return warnings
    }
}

// MARK: - Errors

enum PDFParserError: LocalizedError {
    case cannotOpenDocument
    case noPagesFound
    case parsingFailed(String)
    case noQuestionsDetected
    case answerKeyNotFound
    
    var errorDescription: String? {
        switch self {
        case .cannotOpenDocument: return "PDF dosyası açılamadı"
        case .noPagesFound: return "PDF'de sayfa bulunamadı"
        case .parsingFailed(let msg): return "Ayrıştırma hatası: \(msg)"
        case .noQuestionsDetected: return "Hiç soru tespit edilemedi"
        case .answerKeyNotFound: return "Cevap anahtarı bulunamadı"
        }
    }
}

// MARK: - Manual Correction Helper

extension PDFParserService {
    /// Kullanıcının manuel düzeltmesi için yardımcı yapı
    struct ManualCorrectionData {
        let questionIndex: Int
        let suggestedQuestionText: String
        let suggestedOptions: [(letter: String, text: String)]
        let suggestedAnswer: Int?
        let pageImage: Data? // Sayfa görseli referans için
    }
    
    func prepareManualCorrectionData(from result: ParsedPDFResult) -> [ManualCorrectionData] {
        return result.questions.enumerated().map { index, q in
            ManualCorrectionData(
                questionIndex: index,
                suggestedQuestionText: q.questionText,
                suggestedOptions: q.options.map { ($0.letter, $0.text) },
                suggestedAnswer: q.correctAnswerIndex,
                pageImage: q.images.first?.image.pngData()
            )
        }
    }
}