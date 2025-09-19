# FluidVoice Documentation

Simple, flat documentation structure - one file per feature/topic.

## Structure

```
docs/
├── setup-code-signing.md      # Development environment setup - code signing
├── user-stories.md            # User feedback and feature requests
├── fn-key-research.md         # Technical research for Fn key implementation
├── cgevent-paste-research.md  # CGEvent paste behavior research
├── performance-metrics.md     # App performance analysis
├── permission-*.md            # Permission-related bug documentation
├── ux-issues-summary.md       # UX issues and improvements
├── features/                  # Feature documentation (done/in-progress)
├── bugs/                      # Bug reports and fixes
├── reports/                   # Session reports and progress
└── README.md                  # This file
```

## Development Quick Start

FluidVoice uses `just` for development commands (like `npm run`):

```bash
# Install just (macOS)
brew install just

# See all available commands
just

# Common development workflow
just dev        # Build with output capture
just start      # Start the app
just logs       # Stream logs (in another terminal)
just restart    # Quick restart during development
```

**Key commands:**
- `just dev` - Build development version and run app
- `just build-dev` - Build development version only
- `just build-release` - Build signed production release
- `just run` - Run/restart existing app (no rebuild)
- `just test` - Run tests with parallel execution
- `just logs` - Stream app logs
- `just kill` - Kill running app processes

See `justfile` for all available commands.

## Documentation Guidelines

- **One file per feature** - keep it simple
- **Combine research + spec** in feature files when possible
- **Flat structure** - no nested folders for personal projects

## Contributing

When adding new features or investigating technical solutions:

1. Document research findings in `research/`
2. Create feature specifications in `features/`
3. Update requirements in `requirements/`
4. Document architectural decisions in `architecture/`

This ensures knowledge is preserved and decisions are traceable.