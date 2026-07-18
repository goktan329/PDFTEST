import Foundation

// MARK: - On-Device LLM Service (llama.cpp Swift Binding)

// Bu servis llama.cpp Swift wrapper kullanır
// Model: Llama 3.2 1B/3B Instruct (Q4_K_M quantized, ~1-2GB)
// Veya Phi-3-mini-4k-instruct (Q4, ~2.5GB)

/// Not: Gerçek implementasyon için şu paketlerden biri gerekir:
/// - https://github.com/ggml-org/llama.cpp (C++ core + Swift binding)
/// - https://github.com/ml-explore/mlx-swift (Apple MLX - sadece Apple Silicon)
/// - https://github.com/argmaxinc/WhisperKit pattern'inde llama wrapper

@MainActor
final class LLMService: ObservableObject {
    static let shared = LLMService()
    
    @Published var isModelLoaded: Bool = false
    @Published var loadingProgress: Double = 0.0
    @Published var currentStatus: String = "Model yüklenmedi"
    @Published var isGenerating: Bool = false
    
    // Model konfigürasyonu
    private let modelFileName = "llama-3.2-1b-instruct-q4_k_m.gguf" // Veya phi-3-mini
    private let modelURL: URL?
    private var llamaContext: OpaquePointer? // llama.cpp context pointer
    
    private init() {
        // Bundle'da model varsa onu kullan, yoksa Documents'a indirilmiş olmalı
        if let bundleURL = Bundle.main.url(forResource: "llama-3.2-1b-instruct-q4_k_m", withExtension: "gguf") {
            self.modelURL = bundleURL
        } else {
            let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.modelURL = docsURL.appendingPathComponent(modelFileName)
        }
    }
    
    // MARK: - Model Loading
    
    /// Modeli belleğe yükle (ilk açılışta veya isteğe bağlı)
    func loadModel() async throws {
        guard !isModelLoaded else { return }
        
        currentStatus = "Model dosyası kontrol ediliyor..."
        loadingProgress = 0.1
        
        guard let modelURL = modelURL, FileManager.default.fileExists(atPath: modelURL.path) else {
            currentStatus = "Model dosyası bulunamadı: \(modelFileName)"
            throw LLMEError.modelNotFound(modelFileName)
        }
        
        currentStatus = "Model yükleniyor (bu biraz sürebilir)..."
        loadingProgress = 0.3
        
        // llama.cpp initialization
        // Gerçek implementasyonda: llama_init_from_file, llama_context_default_params, etc.
        // Bu örnekte stub implementation
        
        // Simulate loading for demo
        for i in 1...10 {
            try await Task.sleep(nanoseconds: 200_000_000) // 0.2s
            loadingProgress = 0.3 + 0.6 * Double(i) / 10.0
            currentStatus = "Model yükleniyor... %\(Int(loadingProgress * 100))"
        }
        
        isModelLoaded = true
        currentStatus = "Model hazır"
        loadingProgress = 1.0
    }
    
    func unloadModel() {
        // llama_free_context(llamaContext)
        llamaContext = nil
        isModelLoaded = false
        currentStatus = "Model boşaltıldı"
        loadingProgress = 0.0
    }
    
    // MARK: - Question Solution Generation
    
    struct SolutionRequest {
        let questionText: String
        let options: [String] // ["A) ...", "B) ...", ...]
        let correctAnswerIndex: Int?
        let subject: Subject
        let userLanguage: String // "tr" veya "en"
        let includeStepByStep: Bool
    }
    
    struct SolutionResponse {
        let explanation: String
        let stepByStep: [String]?
        let keyConcepts: [String]
        let estimatedDifficulty: Difficulty
        let alternativeMethods: [String]?
        let generatedAt: Date
        let modelUsed: String
    }
    
    /// Soru için AI çözüm üret
    func generateSolution(for request: SolutionRequest) async throws -> SolutionResponse {
        guard isModelLoaded else {
            throw LLMEError.modelNotLoaded
        }
        
        isGenerating = true
        currentStatus = "Çözüm üretiliyor..."
        defer { isGenerating = false; currentStatus = "Hazır" }
        
        let prompt = buildSolutionPrompt(request)
        
        // llama.cpp inference
        // let response = try await llamaGenerate(prompt: prompt, maxTokens: 1024, temperature: 0.3)
        
        // Stub response for demo
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2s simulation
        
        return SolutionResponse(
            explanation: buildMockExplanation(request),
            stepByStep: buildMockSteps(request),
            keyConcepts: extractKeyConcepts(request),
            estimatedDifficulty: .medium,
            alternativeMethods: ["Pratik yöntem", "Formül yerine mantık yürütme"],
            generatedAt: Date(),
            modelUsed: "Llama-3.2-1B-Instruct-Q4_K_M (local)"
        )
    }
    
    private func buildSolutionPrompt(_ request: SolutionRequest) -> String {
        let optionsText = request.options.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let correctInfo = request.correctAnswerIndex != nil 
            ? "\nDoğru cevap: \(String(Character(UnicodeScalar(65 + request.correctAnswerIndex!))))" 
            : ""
        
        let language = request.userLanguage == "tr" ? "Türkçe" : "English"
        
        return """
        <|system|>
        Sen deneyimli bir \(request.subject.rawValue) öğretmensin. Öğrenciye soruyu adım adım, anlaşılır bir dille çöz. Kısa, öz ve eğitici ol.
        <|user|>
        Ders: \(request.subject.rawValue)
        
        Soru:
        \(request.questionText)
        
        Seçenekler:
        \(optionsText)\(correctInfo)
        
        Lütfen şunları sağla:
        1. Kısa ve net çözüm açıklaması
        2. Adım adım çözüm yolları
        3. Kullanılan ana kavramlar
        4. Alternatif çözüm yöntemleri (varsa)
        
        Yanıt dili: \(language)
        <|assistant|>
        """
    }
    
    // MARK: - Mock Implementation (Demo için)
    
    private func buildMockExplanation(_ request: SolutionRequest) -> String {
        let subject = request.subject.rawValue
        let correctLetter = request.correctAnswerIndex != nil 
            ? String(Character(UnicodeScalar(65 + request.correctAnswerIndex!))) 
            : "?"
        
        return """
        **\(subject) Sorusu Çözümü**
        
        Doğru Cevap: **\(correctLetter)** şıkkı.
        
        **Çözüm Mantığı:**
        Bu soru \(subject.lowercased()) dersinin temel konularından birini test ediyor. Soruyu çözerken şu adımları izleyebilirsiniz:
        
        1. **Soruyu Anlama:** Soruda verilen veriler ve istenen sonuç net bir şekilde belirlenir.
        2. **Uygun Formül/Yöntem Seçimi:** Konuya ait ilgili formül, teorem veya yöntem hatırlanır.
        3. **Hesaplama/Uygulama:** Veriler formüle yerleştirilerek işlemler yapılır.
        4. **Sonuç Kontrolü:** Elde edilen sonuç seçeneklerle karşılaştırılır.
        
        **Neden \(correctLetter) Doğru?**
        Diğer şıklardaki yaygın hatalar: formülü yanlış hatırlamak, işlem sırasını karıştırmak, birim dönüşümünü unutmak veya soruyu yanlış okumak olabilir. \(correctLetter) şıkkında tüm adımlar doğru uygulanmıştır.
        
        **İpucu:** Bu tür sorularda önce "ne isteniyor?" sorusunu kendinize sorun, sonra hangi konu/kasabaya ait olduğunu belirleyin.
        """
    }
    
    private func buildMockSteps(_ request: SolutionRequest) -> [String] {
        return [
            "Soruyu dikkatle okuyun, verilen ve isteneni not edin",
            "Hangi konu/formele ait olduğunu belirleyin",
            "Gerekli formülü yazın ve verileri yerine koyun",
            "İşlemleri adım adım yapın, ara sonuçları kontrol edin",
            "Sonucu seçeneklerle eşleştirin",
            "Cevabı işaretleyin ve bir kez daha gözden geçirin"
        ]
    }
    
    private func extractKeyConcepts(_ request: SolutionRequest) -> [String] {
        // Basit keyword extraction - gerçekte NLP veya LLM'den alınabilir
        let text = request.questionText.lowercased()
        var concepts: [String] = []
        
        let keywordMap: [String: [String]] = [
            "fonksiyon": ["Fonksiyon", "Tanım Kümesi", "Değer Kümesi"],
            "türev": ["Türev", "Limit", "Fark Katsayısı"],
            "integral": ["İntegral", "Alan", "Temel Teorem"],
            "limit": ["Limit", "Sınır Değer", "Sürekli Olma"],
            "geometri": ["Üçgen", "Daire", "Benzerlik", "Pisagor"],
            "trigonometri": ["Sinüs", "Kosinüs", "Tanjant", "Birim Çember"],
            "olasilik": ["Olasılık", "Kombinasyon", "Permütasyon", "Bağımsız Olaylar"],
            "istatistik": ["Ortalama", "Medyan", "Mod", "Standart Sapma"],
            "vektör": ["Vektör", "İç Çarpım", "Dış Çarpım", "Lineer Bağımlılık"],
            "matris": ["Matris", "Determinant", "Ters Matris", "Özdeğer"],
            "kimya": ["Mol", "Molar Kütle", "Reaksiyon", "Denge", "Asit-Baz"],
            "fizik": ["Kuvvet", "Hareket", "Enerji", "İş", "Güç", "Elektrik", "Manyetizma"],
            "biyoloji": ["Hücre", "DNA", "Protein", "Enzim", "Solunum", "Fotosentez"],
            "tarih": ["Tarih", "Dönem", "Olay", "Neden-Sonuç", "Kronoloji"],
            "coğrafya": ["İklim", "Nüfus", "Ekonomi", "Harita", "Jeomorfoloji"],
            "dil": ["Fiil", "İsim", "Sıfat", "Zarf", "Cümle", "Anlatım Bozukluğu"],
            "edebiyat": ["Şiir", "Hikaye", "Roman", "Tiyatro", "Yazar", "Dönem"]
        ]
        
        for (keyword, related) in keywordMap {
            if text.contains(keyword) {
                concepts.append(contentsOf: related)
            }
        }
        
        return Array(Set(concepts)).prefix(5).map { $0 }
    }
    
    // MARK: - Model Download Helper
    
    /// Model dosyasını indir (ilk kurulumda)
    static func downloadModelIfNeeded(progress: @escaping (Double) -> Void) async throws -> URL {
        let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destURL = docsURL.appendingPathComponent("llama-3.2-1b-instruct-q4_k_m.gguf")
        
        if FileManager.default.fileExists(atPath: destURL.path) {
            return destURL
        }
        
        // Hugging Face'den indirme linki (gguf formatında)
        // Gerçek implementasyonda URLSession download task ile
        let modelURL = URL(string: "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf")!
        
        // Bu kısım gerçek implementasyonda download task + progress observation
        // Şimdilik placeholder
        throw LLMEError.downloadRequired(destURL)
    }
}

// MARK: - Errors

enum LLMEError: LocalizedError {
    case modelNotFound(String)
    case modelNotLoaded
    case inferenceFailed(String)
    case downloadRequired(URL)
    case insufficientMemory
    case contextTooLong
    
    var errorDescription: String? {
        switch self {
        case .modelNotFound(let name): return "Model dosyası bulunamadı: \(name). Uygulama içi indirme veya manuel ekleme gerekli."
        case .modelNotLoaded: return "Model henüz yüklenmedi. Önce loadModel() çağrılmalı."
        case .inferenceFailed(let msg): return "Çözüm üretilemedi: \(msg)"
        case .downloadRequired(let url): return "Model indirilmedi. Şuradan indirip \(url.lastPathComponent) olarak kaydedin: \(url)"
        case .insufficientMemory: return "Cihaz belleği yetersiz. Daha küçük model (0.5B) veya bulut API deneyin."
        case .contextTooLong: return "Soru çok uzun, model context limiti aşıldı."
        }
    }
}

// MARK: - Model Info

struct ModelInfo {
    static let recommendedModels: [(name: String, size: String, description: String, url: String)] = [
        ("Llama-3.2-1B-Instruct-Q4_K_M.gguf", "~1.3 GB", "En iyi performans/boyut dengesi, Türkçe destekli", "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF"),
        ("Phi-3-mini-4k-instruct-q4.gguf", "~2.5 GB", "Microsoft modeli, güçlü reasoning", "https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf"),
        ("Llama-3.2-3B-Instruct-Q4_K_M.gguf", "~2.0 GB", "Daha akıllı, daha yavaş", "https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF"),
        ("TinyLlama-1.1B-Chat-v1.0-Q4_K_M.gguf", "~0.7 GB", "En küçük, hızlı ama zayıf reasoning", "https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF")
    ]
    
    static func estimateMemoryRequirement(modelSizeGB: Double) -> Double {
        // llama.cpp: model size + context (4K tokens ~ 16MB) + overhead
        return modelSizeGB * 1.2 + 0.5 // GB cinsinden
    }
}