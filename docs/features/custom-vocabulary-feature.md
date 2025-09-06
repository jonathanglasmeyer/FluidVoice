# Custom Vocabulary Feature

**Status**: 📋 PLANNED  
**Priority**: Medium  
**Complexity**: Low-Medium  
**Estimated Effort**: 2-3 days

## Problem Statement

FluidVoice's transcription often struggles with:
- **Technical terms**: "API" transcribed as "a p i"  
- **Brand names**: "GitHub" becomes "git hub"
- **Specialized vocabulary**: "OAuth" heard as "o auth"
- **User-specific terms**: Company names, product names, acronyms
- **Domain jargon**: Industry-specific terminology

Current semantic correction (MLX/OpenAI/Gemini) provides generic grammar/punctuation fixes but lacks user-customizable vocabulary awareness.

## Solution Overview

### Approach: Enhanced LLM Prompts + Vocabulary Hints

Instead of brittle string replacement, leverage existing semantic correction infrastructure with vocabulary-aware prompts.

**Architecture**: Extend current `SemanticCorrectionService` to include user-defined vocabulary terms in system prompts.

### Technical Implementation

#### 1. Data Storage
```swift
// UserDefaults storage for vocabulary terms
struct VocabularySettings {
    static let key = "customVocabularyTerms"
    
    static func getTerms() -> [String] {
        return UserDefaults.standard.stringArray(forKey: key) ?? []
    }
    
    static func setTerms(_ terms: [String]) {
        UserDefaults.standard.set(terms, forKey: key)
    }
}
```

#### 2. Enhanced Semantic Correction
```swift
// Extend SemanticCorrectionService.swift
private func buildVocabularyAwarePrompt(basePrompt: String) -> String {
    let vocabularyTerms = VocabularySettings.getTerms()
    
    guard !vocabularyTerms.isEmpty else { return basePrompt }
    
    let vocabularyHint = """
    
    Pay special attention to these terms and ensure they are spelled/capitalized correctly:
    \(vocabularyTerms.joined(separator: ", "))
    """
    
    return basePrompt + vocabularyHint
}

// Update existing correction methods
private func correctWithOpenAI(text: String) async -> String {
    // ... existing code ...
    let basePrompt = readPromptFile(name: "cloud_openai_prompt.txt") ?? defaultPrompt
    let vocabularyPrompt = buildVocabularyAwarePrompt(basePrompt: basePrompt)
    
    let body: [String: Any] = [
        "model": "gpt-5-nano",
        "messages": [
            ["role": "system", "content": vocabularyPrompt],
            ["role": "user", "content": text]
        ],
        "max_completion_tokens": 8192
    ]
    // ... rest of existing implementation
}
```

#### 3. Settings UI Integration
```swift
// Add to SettingsView.swift
struct CustomVocabularySection: View {
    @State private var vocabularyTerms: [String] = []
    @State private var newTerm = ""
    
    var body: some View {
        Section("Custom Vocabulary") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Add terms that should be recognized correctly")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Add new term
                HStack {
                    TextField("Enter term (e.g., 'API', 'GitHub')", text: $newTerm)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Button("Add") {
                        addTerm()
                    }
                    .disabled(newTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                
                // Display existing terms
                ForEach(vocabularyTerms, id: \.self) { term in
                    HStack {
                        Text(term)
                        Spacer()
                        Button("Remove") {
                            removeTerm(term)
                        }
                        .foregroundColor(.red)
                    }
                }
            }
        }
        .onAppear {
            vocabularyTerms = VocabularySettings.getTerms()
        }
    }
    
    private func addTerm() {
        let trimmed = newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !vocabularyTerms.contains(trimmed) else { return }
        
        vocabularyTerms.append(trimmed)
        VocabularySettings.setTerms(vocabularyTerms)
        newTerm = ""
    }
    
    private func removeTerm(_ term: String) {
        vocabularyTerms.removeAll { $0 == term }
        VocabularySettings.setTerms(vocabularyTerms)
    }
}
```

## Performance Impact

### Latency Analysis
- **Base semantic correction**: ~1-3s (current)
- **With vocabulary hints**: ~1.2-3.5s (+0.2-0.5s)
- **Additional prompt tokens**: ~50-100 tokens (minimal cost)

**Total impact**: 2-10% latency increase for significantly improved accuracy.

### Why This Approach Works

#### ✅ Pros
- **Context-aware**: LLM understands word boundaries and meaning
- **No false positives**: Unlike string replacement, won't break existing words
- **Leverages existing infrastructure**: Reuses current semantic correction pipeline  
- **Robust**: Benefits from existing `safeMerge()` protection against over-correction
- **User-friendly**: Simple list management in settings

#### ❌ Cons  
- **Slight latency increase**: Additional ~0.2-0.5s per correction
- **Requires semantic correction enabled**: Only works with MLX/Cloud modes
- **LLM dependent**: Quality depends on model's vocabulary understanding

## User Experience

### Workflow
1. **User notices transcription issues**: "GitHub" consistently heard as "git hub"
2. **Adds term to vocabulary**: Settings → Custom Vocabulary → Add "GitHub"  
3. **Immediate improvement**: Next transcription correctly uses "GitHub"
4. **Accumulates domain knowledge**: Build personalized vocabulary over time

### Example Scenarios

#### Software Developer
```
Vocabulary: ["API", "GitHub", "OAuth", "JavaScript", "TypeScript", "MongoDB"]
Before: "I need to set up the a p i with git hub using o auth"
After:  "I need to set up the API with GitHub using OAuth"
```

#### Medical Professional  
```  
Vocabulary: ["MRI", "CT scan", "diagnosis", "pharmaceutical"]
Before: "The m r i shows signs of inflammation"
After:  "The MRI shows signs of inflammation"
```

## Implementation Plan

### Phase 1: Core Infrastructure (Day 1)
- [ ] Add `VocabularySettings` data storage
- [ ] Extend `SemanticCorrectionService` with vocabulary-aware prompts
- [ ] Update OpenAI, Gemini, and MLX correction methods

### Phase 2: User Interface (Day 2)
- [ ] Create `CustomVocabularySection` SwiftUI component
- [ ] Integrate into existing `SettingsView`
- [ ] Add input validation and duplicate prevention

### Phase 3: Testing & Polish (Day 3)
- [ ] Test with various vocabulary terms and scenarios
- [ ] Validate prompt token limits and performance impact
- [ ] Add user documentation and examples

## Technical Considerations

### Prompt Token Limits
- **OpenAI GPT-5-nano**: ~32k context window
- **Gemini 2.5-flash-lite**: ~32k context window  
- **MLX Llama-3.2-3B**: ~8k context window

**Strategy**: Limit vocabulary list to ~50 terms maximum to preserve context for actual transcription content.

### Data Persistence
- Store vocabulary terms in `UserDefaults` for simplicity
- Consider CoreData migration if advanced features needed (categories, frequency tracking)

### Backward Compatibility
- Feature is opt-in (empty vocabulary list = no behavior change)
- Existing semantic correction modes work unchanged
- No impact on users who don't configure custom vocabulary

## Success Metrics

### Before/After Comparison
- **Accuracy improvement**: Measure correction rate for user-specific terms
- **User satisfaction**: Reduced need to manually fix transcriptions
- **Performance impact**: Ensure <10% latency increase

### Target Improvements
- **Technical terms**: 90%+ accuracy for configured vocabulary
- **User adoption**: 30%+ of users configure at least 5 terms
- **Retention**: Users who configure vocabulary show higher app engagement

## Alternative Approaches Considered

### ❌ String Replacement (Rejected)
```swift
// Too brittle - causes false positives
text.replacingOccurrences(of: "api", with: "API", options: .caseInsensitive)
// "Wait" → "WAIt", "Said" → "SAId"
```

### ❌ Whisper Model Fine-tuning (Rejected)  
- Requires extensive ML expertise and training data
- Multiple model variants needed for different domains
- 2.9GB+ storage per custom model
- Weeks of development time

### ❌ Post-Processing NLP (Considered)
- Would require additional NLP frameworks (spaCy, NLTK)
- Complexity doesn't justify benefits over LLM approach
- Additional latency and dependencies

## Related Features

### Future Enhancements
- **Vocabulary categories**: Group terms by domain (Tech, Medical, Legal)
- **Auto-suggestion**: Suggest vocabulary terms based on transcription patterns
- **Import/Export**: Share vocabulary lists between devices/users
- **Contextual hints**: Different vocabulary for different apps or contexts

### Integration Opportunities  
- **History analysis**: Auto-detect frequently mis-transcribed terms
- **Cloud sync**: Backup vocabulary terms to iCloud
- **Voice training**: Combine with accent/pronunciation training

## Conclusion

The Custom Vocabulary feature provides a targeted solution for FluidVoice's most common transcription accuracy issues. By enhancing existing semantic correction infrastructure with user-defined vocabulary hints, we can achieve significant accuracy improvements with minimal complexity and performance impact.

**Key Benefits**:
- 🎯 **Targeted accuracy improvement** for user-specific terminology
- ⚡ **Minimal performance impact** (2-10% latency increase)  
- 🛠️ **Simple implementation** leveraging existing correction pipeline
- 👥 **User-friendly** vocabulary management in settings
- 🔒 **Robust approach** avoiding brittle string replacement issues

This feature represents a high-impact, low-risk improvement that directly addresses user feedback about transcription quality for specialized vocabulary.