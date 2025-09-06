# Developer-First Config File Feature

**Status**: 📋 PLANNED  
**Priority**: Medium  
**Complexity**: Medium  
**Estimated Effort**: 3-4 days

## Problem Statement

FluidVoice currently only supports GUI-based configuration through Settings UI, which creates friction for developer workflows:

- **Team Configuration Sharing**: No easy way to share settings across development teams
- **Version Control**: Settings can't be tracked in dotfiles or project repositories  
- **Scripted Setup**: No programmatic way to configure FluidVoice for automated development environments
- **Power User Features**: Advanced configurations require multiple UI clicks instead of declarative config
- **Reproducible Environments**: Difficult to maintain consistent FluidVoice setup across multiple machines

## Solution Overview

### Approach: JSON Config File with Live UI Sync

Implement developer-friendly JSON configuration file support following the **Claude Code/VS Code** model:
- JSON config file at `~/.config/fluidvoice/config.json`
- **Bi-directional sync** between Settings UI and config file
- **Live file watching** for external config changes
- **No import/export UI** - developers work directly with filesystem

### Technical Implementation

#### 1. Config File Structure
```json
{
  "$schema": "https://fluidvoice.app/schemas/config-v1.json",
  "transcription": {
    "provider": "local",
    "model": "large-v3",
    "language": "de",
    "forceLanguage": true
  },
  "semanticCorrection": {
    "mode": "localMLX",
    "modelRepo": "mlx-community/Llama-3.2-3B-Instruct-4bit",
    "maxChangeRatio": 0.6
  },
  "customVocabulary": {
    "enabled": true,
    "terms": ["API", "GitHub", "OAuth", "TypeScript", "Claude"]
  },
  "hotkeys": {
    "primary": "cmd+shift+space",
    "fnKeySupport": true,
    "recordingModes": {
      "enabled": true,
      "holdThreshold": 200,
      "armedTimeout": 7000
    }
  },
  "performance": {
    "preloadOnStartup": true,
    "warmupModels": true,
    "modelCacheLimit": 3
  },
  "ui": {
    "showWelcomeOnStartup": false,
    "recordingWindowPosition": "center"
  }
}
```

#### 2. Swift Config Management
```swift
import Foundation
import Combine

struct FluidVoiceConfig: Codable, Equatable {
    let transcription: TranscriptionConfig
    let semanticCorrection: SemanticCorrectionConfig
    let customVocabulary: CustomVocabularyConfig
    let hotkeys: HotkeyConfig
    let performance: PerformanceConfig
    let ui: UIConfig
    
    static var `default`: FluidVoiceConfig {
        // Return sensible defaults matching current UserDefaults behavior
    }
}

class ConfigManager: ObservableObject {
    @Published var config: FluidVoiceConfig
    
    private let configPath: URL
    private var fileSystemWatcher: DispatchSourceFileSystemObject?
    private let logger = Logger(subsystem: "com.fluidvoice.app", category: "ConfigManager")
    
    init() {
        // Config file location following XDG Base Directory spec
        let configDir = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".config/fluidvoice", isDirectory: true)
        
        configPath = configDir.appendingPathComponent("config.json")
        
        // Create config directory if needed
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        
        // Load existing config or use defaults
        config = loadConfigFromFile() ?? .default
        
        // Start watching for external file changes
        startFileWatcher()
        
        // If no config file exists, create one with current defaults
        if !FileManager.default.fileExists(atPath: configPath.path) {
            saveConfigToFile()
        }
    }
    
    private func loadConfigFromFile() -> FluidVoiceConfig? {
        do {
            let data = try Data(contentsOf: configPath)
            let config = try JSONDecoder().decode(FluidVoiceConfig.self, from: data)
            logger.info("Config loaded from file: \(configPath.path)")
            return config
        } catch {
            logger.warning("Failed to load config from file: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func saveConfigToFile() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(config)
            try data.write(to: configPath, options: .atomic)
            logger.info("Config saved to file: \(configPath.path)")
        } catch {
            logger.error("Failed to save config to file: \(error.localizedDescription)")
        }
    }
    
    private func startFileWatcher() {
        guard let fileHandle = FileHandle(forReadingAtPath: configPath.path) else { return }
        
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileHandle.fileDescriptor,
            eventMask: .write,
            queue: DispatchQueue.global()
        )
        
        source.setEventHandler { [weak self] in
            DispatchQueue.main.async {
                self?.reloadConfigFromFile()
            }
        }
        
        source.resume()
        fileSystemWatcher = source
    }
    
    private func reloadConfigFromFile() {
        if let newConfig = loadConfigFromFile(), newConfig != config {
            logger.info("Config file changed externally, reloading...")
            config = newConfig
        }
    }
    
    // Called by Settings UI when user makes changes
    func updateConfig(_ newConfig: FluidVoiceConfig) {
        guard newConfig != config else { return }
        config = newConfig
        saveConfigToFile()
    }
}
```

#### 3. Settings UI Integration
```swift
struct SettingsView: View {
    @StateObject private var configManager = ConfigManager()
    
    var body: some View {
        TabView {
            TranscriptionSettingsView(config: $configManager.config)
                .onChange(of: configManager.config) { newConfig in
                    configManager.updateConfig(newConfig)
                }
            
            // ... other settings tabs
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Open Config File") {
                    NSWorkspace.shared.selectFile(
                        configManager.configPath.path,
                        inFileViewerRootedAtPath: configManager.configPath.deletingLastPathComponent().path
                    )
                }
            }
        }
        .onAppear {
            // Small disclosure about config file location
            Text("Configuration: ~/.config/fluidvoice/config.json")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
```

#### 4. JSON Schema Support
```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "FluidVoice Configuration",
  "type": "object",
  "properties": {
    "transcription": {
      "type": "object",
      "properties": {
        "provider": {
          "type": "string",
          "enum": ["local", "openai", "gemini", "parakeet"],
          "description": "Speech-to-text provider"
        },
        "model": {
          "type": "string", 
          "enum": ["tiny", "base", "small", "large-v3"],
          "description": "Whisper model size"
        }
      }
    }
  }
}
```

## Developer Benefits

### ✅ Team Configuration Management
```bash
# Share team config
scp ~/.config/fluidvoice/config.json teammate@server:~/.config/fluidvoice/

# Version control integration
cd ~/dotfiles
ln -s ~/.config/fluidvoice/config.json fluidvoice.json
git add fluidvoice.json && git commit -m "Add FluidVoice config"
```

### ✅ Scripted Environment Setup
```bash
#!/bin/bash
# development-setup.sh
mkdir -p ~/.config/fluidvoice
cat > ~/.config/fluidvoice/config.json << 'EOF'
{
  "transcription": {
    "provider": "local",
    "model": "tiny",
    "language": "en"
  },
  "performance": {
    "preloadOnStartup": true
  }
}
EOF
```

### ✅ Programmatic Configuration
```bash
# Switch to faster model for development
jq '.transcription.model = "tiny"' ~/.config/fluidvoice/config.json > tmp && mv tmp ~/.config/fluidvoice/config.json

# Enable vocabulary for current project
jq '.customVocabulary.terms += ["React", "Next.js", "Tailwind"]' ~/.config/fluidvoice/config.json > tmp && mv tmp ~/.config/fluidvoice/config.json
```

### ✅ IDE Integration
- **VS Code**: JSON schema provides autocomplete and validation
- **Vim/Neovim**: Syntax highlighting and formatting
- **JetBrains IDEs**: JSON structure navigation

## Implementation Plan

### Phase 1: Core Config Infrastructure (Day 1-2)
- [ ] Define `FluidVoiceConfig` Swift structs with Codable conformance
- [ ] Implement `ConfigManager` with file loading/saving
- [ ] Create config directory and default config file generation
- [ ] Add basic file system watching for external changes

### Phase 2: Settings UI Integration (Day 2-3)
- [ ] Modify existing Settings views to work with `FluidVoiceConfig`
- [ ] Implement bi-directional sync between UI and config file
- [ ] Add "Open Config File" button to Settings toolbar
- [ ] Add config file path disclosure in Settings footer

### Phase 3: Developer Experience (Day 3-4)
- [ ] Create JSON schema file for IDE support
- [ ] Add config validation and error handling
- [ ] Implement config migration for future schema changes
- [ ] Write developer documentation with examples

### Phase 4: Testing & Polish (Day 4)
- [ ] Unit tests for ConfigManager load/save/watch functionality
- [ ] Integration tests for UI ↔ config sync
- [ ] Test config validation and error recovery
- [ ] Performance testing for file watching overhead

## Technical Considerations

### Config File Location
Following **XDG Base Directory Specification**:
- Primary: `~/.config/fluidvoice/config.json`
- Fallback: `~/.fluidvoice/config.json` (for systems without .config)

### Migration Strategy
```swift
struct ConfigMigration {
    static func migrateFromUserDefaults() -> FluidVoiceConfig {
        // Read existing UserDefaults and convert to FluidVoiceConfig
        // Preserve user's current settings during transition
    }
    
    static func migrateConfigVersion(from: Int, to: Int, config: Data) -> Data {
        // Handle future config schema changes
    }
}
```

### Error Handling
- **Invalid JSON**: Fall back to defaults, log error, preserve original file
- **Missing file**: Create default config file automatically
- **Permission errors**: Log warning, continue with in-memory config
- **Schema validation**: Non-blocking warnings for unknown properties

### Performance Considerations
- **File watching overhead**: Minimal impact using DispatchSource
- **JSON parsing**: One-time cost on app startup and external changes
- **Memory usage**: Config object is lightweight (<1KB in memory)

## User Experience

### Seamless Integration
- **No workflow disruption**: Existing Settings UI continues to work identically
- **Progressive disclosure**: Config file mentioned but not required knowledge
- **Live synchronization**: Changes in either UI or file are immediately reflected

### Developer Discovery
```swift
// Settings view footer
HStack {
    Image(systemName: "gear")
    Text("Advanced configuration available at")
    Text("~/.config/fluidvoice/config.json")
        .font(.system(.caption, design: .monospaced))
        .foregroundColor(.secondary)
    Button("Open") {
        NSWorkspace.shared.selectFile(configPath.path, inFileViewerRootedAtPath: configDir.path)
    }
    .buttonStyle(.borderless)
}
.font(.caption)
.padding(.top, 8)
```

## Alternative Approaches Considered

### ❌ TOML Configuration
- Less familiar to developers than JSON
- No native Swift parsing support
- Limited IDE tooling compared to JSON

### ❌ YAML Configuration  
- Indentation-sensitive syntax prone to errors
- No native Swift parsing support
- Overkill for FluidVoice's configuration complexity

### ❌ Import/Export UI Buttons
- Adds UI complexity without significant benefit
- Developers prefer direct filesystem access
- Against Unix philosophy of text-based configuration

### ❌ XML/Plist Configuration
- Verbose and difficult to edit manually
- Not developer-friendly format
- macOS-specific, limits cross-platform potential

## Related Features

### Future Enhancements
- **Project-specific configs**: Support `.fluidvoice/config.json` in project directories
- **Environment variables**: Override config values with `FLUIDVOICE_*` env vars
- **Config templates**: Predefined configs for common use cases
- **Validation CLI**: Command-line tool to validate config files

### Integration Opportunities
- **Custom Vocabulary**: Config file provides better vocabulary management than Settings UI
- **Hotkey Configuration**: Complex key combinations easier to define in JSON
- **Model Management**: Declarative model installation and caching policies

## Success Metrics

### Developer Adoption
- **Config file usage**: 40%+ of users create config files within 30 days
- **GitHub integration**: Evidence of FluidVoice configs in dotfiles repositories
- **Community sharing**: Examples of shared team configurations

### Technical Quality
- **Zero UI regressions**: All existing Settings functionality preserved
- **File sync reliability**: <1% sync failures between UI and config file
- **Performance impact**: <10ms additional app startup time

### Documentation Quality
- **Clear examples**: Working config examples for common scenarios
- **Schema coverage**: 100% of config options documented with JSON schema
- **Migration guide**: Step-by-step guide for existing users

## Conclusion

The Developer-First Config File feature transforms FluidVoice from a GUI-only application into a **developer-friendly tool** that fits naturally into modern development workflows. By following established patterns from tools like VS Code and Claude Code, we provide:

- **Zero learning curve** for developers familiar with JSON configuration
- **Powerful automation** capabilities for team environments and CI/CD
- **Backwards compatibility** with existing Settings UI workflows  
- **Future extensibility** for advanced configuration scenarios

This feature positions FluidVoice as a serious tool for developer productivity while maintaining accessibility for all user types. The bi-directional sync approach ensures no user is forced to choose between UI convenience and configuration power.

**Key Benefits**:
- 🧑‍💻 **Developer-first** design following industry standards
- 📁 **Version controllable** configuration for team collaboration
- 🤖 **Automation-ready** for scripted development environments
- 🔄 **Zero workflow disruption** for existing UI users
- 🚀 **Enhanced positioning** as a professional developer tool