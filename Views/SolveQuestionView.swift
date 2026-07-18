import SwiftUI
import PencilKit
import UniformTypeIdentifiers

// MARK: - Solve Question View (Ana Çözüm Ekranı)

struct SolveQuestionView: View {
    @StateObject var viewModel: SolveSessionViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var showExitConfirm = false
    @State private var showQuestionList = false
    @State private var showOptionsSheet = false
    @State private var canvasScale: CGFloat = 1.0
    @State private var lastCanvasScale: CGFloat = 1.0
    
    // PencilKit tool picker
    @State private var canvasView = PKCanvasView()
    @State private var toolPicker = PKToolPicker()
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                // Ana içerik
                VStack(spacing: 0) {
                    // Üst bar: İlerleme, net, zaman
                    topBar
                    
                    // Soru alanı
                    ScrollView {
                        VStack(spacing: 16) {
                            // Soru metni ve görsel
                            questionContent
                            
                            // Şıklar
                            optionsSection
                            
                            // Sonuç gösterimi
                            if viewModel.showResult {
                                resultSection
                            }
                            
                            // AI Çözüm
                            if viewModel.showAIExplanation {
                                aiExplanationSection
                            }
                            
                            // Çözüm notu
                            solutionNoteSection
                            
                            // Alt boşluk (klavye/araçlar için)
                            Color.clear.frame(height: 100)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    }
                    
                    // Alt navigasyon bar
                    bottomNavigationBar
                }
                
                // PencilKit Tool Picker (iPad'de yan taraf, iPhone'de alt bar)
                // iPhone için tool picker'ı sheet olarak göster
            }
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showExitConfirm = true }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("Soru \(viewModel.currentStats.currentQuestionNumber) / \(viewModel.currentStats.totalQuestions)")
                        .font(.headline)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        Button(action: { showQuestionList = true }) {
                            Image(systemName: "list.bullet")
                        }
                        Button(action: { showOptionsSheet = true }) {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .confirmationDialog("Çıkmak istediğinizden emin misiniz?", isPresented: $showExitConfirm) {
                Button("Kaydet ve Çık", role: .destructive) {
                    viewModel.saveAttempt()
                    dismiss()
                }
                Button("Kaydetmeden Çık", role: .cancel) {
                    dismiss()
                }
            }
            .sheet(isPresented: $showQuestionList) {
                QuestionListSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $showOptionsSheet) {
                QuestionOptionsSheet(viewModel: viewModel)
            }
            .onAppear {
                setupCanvas()
            }
        }
    }
    
    // MARK: - Top Bar
    
    private var topBar: some View {
        VStack(spacing: 8) {
            // İlerleme çubuğu
            ProgressView(value: viewModel.currentStats.progress)
                .progressViewStyle(.linear)
                .tint(.blue)
                .padding(.horizontal, 16)
            
            // İstatistikler
            HStack(spacing: 20) {
                StatItem(icon: "checkmark.circle.fill", color: .green, value: "\(viewModel.currentStats.correct)", label: "Doğru")
                StatItem(icon: "xmark.circle.fill", color: .red, value: "\(viewModel.currentStats.wrong)", label: "Yanlış")
                StatItem(icon: "circle.fill", color: .gray, value: "\(viewModel.currentStats.blank)", label: "Boş")
                StatItem(icon: "function", color: .blue, value: String(format: "%.2f", viewModel.currentStats.net), label: "Net")
            }
            .font(.caption)
            .padding(.horizontal, 16)
            
            // Zaman
            HStack {
                Image(systemName: "timer")
                Text(formatTime(viewModel.timeElapsed))
                Spacer()
                Text("Toplam: \(formatTime(viewModel.session?.durationSeconds ?? 0))")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .background(.regularMaterial)
    }
    
    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }
    
    // MARK: - Question Content
    
    private var questionContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Ders/Etiketler
            if let question = viewModel.currentQuestion {
                HStack(spacing: 8) {
                    if let subject = question.pdfSource?.subject {
                        Label(subject.rawValue, systemImage: subject.icon)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    
                    if !question.tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(question.tags.prefix(3), id: \.self) { tag in
                                    Text(tag)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.15))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Zorluk
                    if question.difficulty != .medium {
                        Text(question.difficulty == .hard ? "🔴 Zor" : "🟢 Kolay")
                            .font(.caption)
                    }
                }
            }
            
            // Soru metni
            if let question = viewModel.currentQuestion {
                Text(question.questionText)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Soru görseli varsa
                if let imageData = question.questionImageData,
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            
            // Çizim alanı (PencilKit)
            drawingCanvas
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    // MARK: - Drawing Canvas
    
    private var drawingCanvas: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Çalışma Alanı")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Button(action: { viewModel.clearDrawing() }) {
                    Label("Temizle", systemImage: "trash")
                        .font(.caption)
                }
                .disabled(viewModel.drawing.bounds.isEmpty)
            }
            
            // PKCanvasView wrapper
            CanvasView(
                drawing: $viewModel.drawing,
                toolPicker: $toolPicker,
                onDrawingChanged: { newDrawing in
                    viewModel.updateDrawing(newDrawing)
                }
            )
            .frame(height: 250)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.separator, lineWidth: 1)
            )
        }
    }
    
    // MARK: - Options Section
    
    private var optionsSection: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Seçenekler")
                    .font(.headline)
                Spacer()
                if viewModel.showResult {
                    Text(viewModel.currentAttempt?.status.rawValue ?? "")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(statusColor(viewModel.currentAttempt?.status).opacity(0.2))
                        .foregroundStyle(statusColor(viewModel.currentAttempt?.status))
                        .clipShape(Capsule())
                }
            }
            
            if let question = viewModel.currentQuestion {
                LazyVStack(spacing: 8) {
                    ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                        OptionRow(
                            index: index,
                            letter: question.optionLetters[index],
                            text: option.text,
                            isSelected: viewModel.selectedAnswerIndex == index,
                            isMarked: viewModel.markedOptions.contains(index),
                            isCorrect: viewModel.showResult && question.correctAnswerIndex == index,
                            isWrong: viewModel.showResult && viewModel.selectedAnswerIndex == index && question.correctAnswerIndex != index,
                            onTap: { viewModel.selectOption(index) },
                            onLongPress: { viewModel.toggleOptionMark(index) }
                        )
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    private func statusColor(_ status: AnswerStatus?) -> Color {
        switch status {
        case .correct: return .green
        case .wrong: return .red
        case .blank: return .orange
        case .unanswered: return .gray
        case nil: return .gray
        }
    }
    
    // MARK: - Result Section
    
    private var resultSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: resultIcon)
                    .font(.title2)
                    .foregroundStyle(resultColor)
                Text(resultTitle)
                    .font(.headline)
                    .foregroundStyle(resultColor)
                Spacer()
            }
            
            if let question = viewModel.currentQuestion,
               let correctIndex = question.correctAnswerIndex {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Doğru Cevap: **\(question.optionLetters[correctIndex])**")
                        .font(.body)
                    
                    if let explanation = question.explanation {
                        Text("Açıklama: \(explanation)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if let userNote = question.userSolutionNote, !userNote.isEmpty {
                        Text("📝 Notunuz: \(userNote)")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // AI Çözüm butonu
            if !viewModel.showAIExplanation {
                Button(action: {
                    Task { await viewModel.generateAIExplanation() }
                }) {
                    HStack {
                        if viewModel.isGeneratingAI {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "brain.head.profile")
                        }
                        Text(viewModel.isGeneratingAI ? "Üretiliyor..." : "AI Çözüm İste")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isGeneratingAI || !LLMService.shared.isModelLoaded)
            }
        }
        .padding(16)
        .background(resultColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private var resultIcon: String {
        switch viewModel.currentAttempt?.status {
        case .correct: return "checkmark.circle.fill"
        case .wrong: return "xmark.circle.fill"
        case .blank: return "circle.fill"
        default: return "questionmark.circle.fill"
        }
    }
    
    private var resultColor: Color {
        statusColor(viewModel.currentAttempt?.status)
    }
    
    private var resultTitle: String {
        switch viewModel.currentAttempt?.status {
        case .correct: return "Doğru! 🎉"
        case .wrong: return "Yanlış"
        case .blank: return "Boş Bırakıldı"
        default: return "Cevaplanmadı"
        }
    }
    
    // MARK: - AI Explanation Section
    
    private var aiExplanationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("AI Çözümü", systemImage: "brain.head.profile")
                    .font(.headline)
                Spacer()
                Button(action: { viewModel.showAIExplanation = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
            
            ScrollView {
                Text(viewModel.aiExplanation)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 300)
        }
        .padding(16)
        .background(Color.purple.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Solution Note Section
    
    private var solutionNoteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Kendi Çözüm Notunuz", systemImage: "note.text")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Button(action: { viewModel.toggleQualityMark() }) {
                    Image(systemName: viewModel.showQualityMark ? "star.fill" : "star")
                        .foregroundStyle(viewModel.showQualityMark ? .yellow : .secondary)
                        .font(.title3)
                }
            }
            
            TextEditor(text: $viewModel.userSolutionNote)
                .font(.body)
                .frame(minHeight: 100)
                .padding(12)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onChange(of: viewModel.userSolutionNote) { _, newValue in
                    viewModel.saveSolutionNote(newValue)
                }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    // MARK: - Bottom Navigation Bar
    
    private var bottomNavigationBar: some View {
        HStack(spacing: 20) {
            Button(action: { viewModel.goToPreviousQuestion() }) {
                Label("Önceki", systemImage: "chevron.left")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.canGoPrevious)
            
            Button(action: { viewModel.goToNextQuestion() }) {
                Label("Sonraki", systemImage: "chevron.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canGoNext)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }
    
    // MARK: - Canvas Setup
    
    private func setupCanvas() {
        canvasView.drawing = viewModel.drawing
        canvasView.drawingPolicy = .anyInput // Parmak + Apple Pencil
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        
        toolPicker.setVisible(true, forFirstResponder: canvasView)
        toolPicker.addObserver(canvasView)
        canvasView.becomeFirstResponder()
    }
}

// MARK: - Option Row

struct OptionRow: View {
    let index: Int
    let letter: String
    let text: String
    let isSelected: Bool
    let isMarked: Bool
    let isCorrect: Bool
    let isWrong: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Şık harfi
                ZStack {
                    Circle()
                        .fill(backgroundColor)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Circle()
                                .stroke(borderColor, lineWidth: 2)
                        )
                    
                    if isCorrect {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.green)
                    } else if isWrong {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.red)
                    } else if isMarked {
                        Image(systemName: "slash.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.orange)
                    } else {
                        Text(letter)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(textColor)
                    }
                }
                
                // Şık metni
                Text(text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .strikethrough(isMarked)
                    .opacity(isMarked ? 0.5 : 1.0)
                
                // Seçim işareti
                if isSelected && !isCorrect && !isWrong {
                    Image(systemName: "circle.inset.filled")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: isSelected || isCorrect || isWrong ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in onLongPress() }
        )
        .contextMenu {
            Button(action: onTap) {
                Label(isSelected ? "Seçimi Kaldır" : "Bu Şıkkı Seç", systemImage: isSelected ? "xmark.circle" : "checkmark.circle")
            }
            Button(action: onLongPress) {
                Label(isMarked ? "İşareti Kaldır" : "Elimle (İşaretle)", systemImage: isMarked ? "slash.circle" : "minus.circle")
            }
            if !isSelected {
                Button(role: .destructive) {
                    // Boş bırak
                } label: {
                    Label("Boş Bırak", systemImage: "circle")
                }
            }
        }
    }
    
    private var backgroundColor: Color {
        if isCorrect { return .green.opacity(0.15) }
        if isWrong { return .red.opacity(0.15) }
        if isSelected { return .blue.opacity(0.1) }
        if isMarked { return .orange.opacity(0.1) }
        return Color(.systemGray6)
    }
    
    private var borderColor: Color {
        if isCorrect { return .green }
        if isWrong { return .red }
        if isSelected { return .blue }
        if isMarked { return .orange }
        return Color.separator
    }
    
    private var rowBackground: Color {
        if isCorrect { return Color.green.opacity(0.08) }
        if isWrong { return Color.red.opacity(0.08) }
        if isSelected { return Color.blue.opacity(0.05) }
        if isMarked { return Color.orange.opacity(0.05) }
        return Color(.systemBackground)
    }
    
    private var textColor: Color {
        if isCorrect { return .green }
        if isWrong { return .red }
        if isSelected { return .blue }
        return .primary
    }
}

// MARK: - PKCanvasView Wrapper

struct CanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    @Binding var toolPicker: PKToolPicker
    let onDrawingChanged: (PKDrawing) -> Void
    
    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawing = drawing
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.delegate = context.coordinator
        
        toolPicker.setVisible(true, forFirstResponder: canvas)
        toolPicker.addObserver(canvas)
        canvas.becomeFirstResponder()
        
        return canvas
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        if uiView.drawing != drawing {
            uiView.drawing = drawing
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PKCanvasViewDelegate {
        let parent: CanvasView
        
        init(_ parent: CanvasView) {
            self.parent = parent
        }
        
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
            parent.onDrawingChanged(canvasView.drawing)
        }
    }
}

// MARK: - Stat Item

struct StatItem: View {
    let icon: String
    let color: Color
    let value: String
    let label: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(value)
                .fontWeight(.semibold)
            Text(label)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Question List Sheet

struct QuestionListSheet: View {
    @ObservedObject var viewModel: SolveSessionViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(Array((viewModel.session?.questionIds ?? []).enumerated()), id: \.offset) { index, questionId in
                    Button(action: {
                        viewModel.goToQuestion(at: index)
                        dismiss()
                    }) {
                        HStack {
                            Text("Soru \(index + 1)")
                                .font(.body)
                            Spacer()
                            if let attempt = attemptForQuestion(questionId) {
                                Image(systemName: statusIcon(attempt.status))
                                    .foregroundStyle(statusColor(attempt.status))
                            } else {
                                Image(systemName: "circle")
                                    .foregroundStyle(.secondary)
                            }
                            
                            if index == viewModel.session?.currentQuestionIndex {
                                Image(systemName: "arrow.right.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .navigationTitle("Soru Listesi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    private func attemptForQuestion(_ id: UUID) -> UserAttemptModel? {
        viewModel.session?.attempts.first { $0.question?.id == id }
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
}

// MARK: - Question Options Sheet

struct QuestionOptionsSheet: View {
    @ObservedObject var viewModel: SolveSessionViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section("Soru İşlemleri") {
                    Button(action: {
                        viewModel.markAsBlank()
                        dismiss()
                    }) {
                        Label("Boş Bırak", systemImage: "circle")
                    }
                    
                    Button(action: {
                        viewModel.clearSelection()
                        dismiss()
                    }) {
                        Label("Seçimi Temizle", systemImage: "eraser")
                    }
                    
                    Button(action: {
                        viewModel.toggleQualityMark()
                        dismiss()
                    }) {
                        Label(viewModel.showQualityMark ? "Kaliteli İşaretini Kaldır" : "Kaliteli Olarak İşaretle",
                              systemImage: viewModel.showQualityMark ? "star.slash" : "star")
                    }
                }
                
                Section("AI Yardımı") {
                    if LLMService.shared.isModelLoaded {
                        Button(action: {
                            Task { await viewModel.generateAIExplanation() }
                            dismiss()
                        }) {
                            Label("AI Çözüm İste", systemImage: "brain.head.profile")
                        }
                        .disabled(viewModel.isGeneratingAI)
                    } else {
                        Label("Model Yüklü Değil", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section("Navigasyon") {
                    Button(action: {
                        viewModel.goToPreviousQuestion()
                        dismiss()
                    }) {
                        Label("Önceki Soru", systemImage: "chevron.left")
                    }
                    .disabled(!viewModel.canGoPrevious)
                    
                    Button(action: {
                        viewModel.goToNextQuestion()
                        dismiss()
                    }) {
                        Label("Sonraki Soru", systemImage: "chevron.right")
                    }
                    .disabled(!viewModel.canGoNext)
                }
            }
            .navigationTitle("Seçenekler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}