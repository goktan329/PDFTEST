import Foundation
import SwiftUI
import CoreGraphics
import UniformTypeIdentifiers

// MARK: - Color Extensions

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: Double(a)/255)
    }
    
    func toHex() -> String? {
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return String(format: "#%02X%02X%02X", Int(r*255), Int(g*255), Int(b*255))
    }
}

// MARK: - Date Extensions

extension Date {
    func relativeFormatted() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = Locale(identifier: "tr_TR")
        return formatter.localizedString(for: self, relativeTo: Date())
    }
    
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }
    
    var endOfDay: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!.addingTimeInterval(-1)
    }
}

// MARK: - String Extensions

extension String {
    func trimmed() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func isNotEmpty() -> Bool {
        !trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    func fuzzyMatch(_ pattern: String) -> Bool {
        let pattern = pattern.lowercased()
        let text = self.lowercased()
        var patternIndex = pattern.startIndex
        for char in text {
            if patternIndex < pattern.endIndex && char == pattern[patternIndex] {
                patternIndex = pattern.index(after: patternIndex)
            }
        }
        return patternIndex == pattern.endIndex
    }
}

// MARK: - Array Extensions

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Dictionary Extensions

extension Dictionary {
    func mapValues<T>(_ transform: (Value) -> T) -> [Key: T] {
        var result: [Key: T] = [:]
        for (key, value) in self {
            result[key] = transform(value)
        }
        return result
    }
}

// MARK: - View Extensions

extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    func onTapGestureHideKeyboard() -> some View {
        self.onTapGesture { hideKeyboard() }
    }
    
    func cardStyle(padding: CGFloat = 16, cornerRadius: CGFloat = 16, shadow: Bool = true) -> some View {
        self
            .padding(padding)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: .black.opacity(shadow ? 0.05 : 0), radius: 8, x: 0, y: 2)
    }
    
    func bordered(cornerRadius: CGFloat = 12, color: Color = .separator, lineWidth: CGFloat = 1) -> some View {
        self.overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(color, lineWidth: lineWidth)
        )
    }
}

// MARK: - SwiftData Helpers

import SwiftData

extension ModelContext {
    func fetchFirst<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> T? {
        try fetch(descriptor).first
    }
    
    func fetchCount<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> Int {
        try fetch(descriptor).count
    }
    
    func deleteAll<T: PersistentModel>(_ type: T.Type) throws {
        let descriptor = FetchDescriptor<T>()
        let objects = try fetch(descriptor)
        for object in objects {
            delete(object)
        }
    }
}

// MARK: - Spaced Repetition Algorithm

struct SpacedRepetitionScheduler {
    /// Basit SM-2 varyantı: 1, 3, 7, 15, 30, 60 gün
    static let intervals: [Int] = [1, 3, 7, 15, 30, 60, 120]
    
    static func nextReviewDate(for entry: WrongQuestionBankModel) -> Date {
        let reviewCount = entry.reviewCount
        let intervalIndex = min(reviewCount, intervals.count - 1)
        let days = intervals[intervalIndex]
        return Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
    }
    
    static func shouldReviewNow(_ entry: WrongQuestionBankModel) -> Bool {
        guard let nextReview = entry.nextReviewDate else { return true }
        return nextReview <= Date() && !entry.isResolved
    }
}

// MARK: - Net Score Calculator

struct NetScoreCalculator {
    static let wrongPenalty: Double = 0.25 // 4 yanlış = 1 doğru
    
    static func calculate(correct: Int, wrong: Int, blank: Int) -> Double {
        Double(correct) - Double(wrong) * wrongPenalty
    }
    
    static func calculate(from attempts: [UserAttemptModel]) -> (correct: Int, wrong: Int, blank: Int, net: Double) {
        let correct = attempts.filter { $0.status == .correct }.count
        let wrong = attempts.filter { $0.status == .wrong }.count
        let blank = attempts.filter { $0.status == .blank }.count
        let net = calculate(correct: correct, wrong: wrong, blank: blank)
        return (correct, wrong, blank, net)
    }
}

// MARK: - File Size Formatter

struct FileSizeFormatter {
    static func format(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Haptic Feedback

struct HapticFeedback {
    static func light() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
    
    static func medium() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
    
    static func heavy() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
    }
    
    static func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
    
    static func warning() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }
    
    static func error() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
    }
}

// MARK: - PKDrawing Helpers

import PencilKit

extension PKDrawing {
    var isEmpty: Bool {
        bounds.isEmpty || strokes.isEmpty
    }
    
    var strokeCount: Int {
        strokes.count
    }
    
    func scaled(to size: CGSize) -> PKDrawing {
        let scaleX = size.width / bounds.width
        let scaleY = size.height / bounds.height
        let scale = min(scaleX, scaleY)
        var transform = CGAffineTransform(scaleX: scale, y: scale)
        return transformed(using: &transform)
    }
}

// MARK: - Constants

enum AppConstants {
    static let minQuestionCountForSession = 5
    static let maxQuestionCountForSession = 100
    static let defaultEstimatedTimePerQuestion = 90 // seconds
    static let pdfImportDirectoryName = "PDFImports"
    static let modelDirectoryName = "Models"
    
    enum UserDefaultsKeys {
        static let autoSaveDrawing = "autoSaveDrawing"
        static let hapticFeedback = "hapticFeedback"
        static let showTimer = "showTimer"
        static let autoAdvanceOnAnswer = "autoAdvanceOnAnswer"
        static let penColorHex = "penColorHex"
        static let penWidth = "penWidth"
        static let preferredLanguage = "preferredLanguage"
        static let enableAISolutions = "enableAISolutions"
    }
}

// MARK: - Debug Helpers

#if DEBUG
extension View {
    func debugBorder(_ color: Color = .red) -> some View {
        self.border(color, width: 1)
    }
    
    func debugBackground(_ color: Color = .red.opacity(0.3)) -> some View {
        self.background(color)
    }
}

func debugPrint(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    #if DEBUG
    let output = items.map { "\($0)" }.joined(separator: separator)
    print("🐛 \(output)", terminator: terminator)
    #endif
}
#endif