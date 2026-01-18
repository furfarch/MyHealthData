# GitHub Copilot Instructions Guide

This directory contains GitHub Copilot instructions that help the AI understand this project's conventions, patterns, and best practices.

## Structure

### Repository-Wide Instructions

**`copilot-instructions.md`** - Main instructions that apply to the entire repository:
- Project overview and technology stack
- Architecture patterns
- Coding standards
- Testing guidelines
- Build and test commands
- Security and privacy guidelines
- Common code patterns

### Path-Specific Instructions

The `instructions/` directory contains specialized guidelines for different parts of the codebase:

- **`models.instructions.md`** - Applies to `MyHealthData/Models/**/*.swift`
  - SwiftData model patterns
  - Relationship definitions
  - Identity and timestamp handling

- **`views.instructions.md`** - Applies to `MyHealthData/Views/**/*.swift`
  - SwiftUI view structure
  - Data access patterns
  - Preview provider guidelines

- **`services.instructions.md`** - Applies to `MyHealthData/Services/**/*.swift`
  - Service layer organization
  - CloudKit integration patterns
  - Error handling

- **`tests.instructions.md`** - Applies to `MyHealthDataTests/**/*.swift`
  - Swift Testing framework usage
  - Test patterns and examples
  - Testing persistence and models

## How It Works

GitHub Copilot automatically reads these instructions when:
- You're writing code in matching files
- You ask questions about the codebase
- You request code reviews
- You're using Copilot's coding agent

The instructions help Copilot generate code that:
- Follows project conventions
- Uses the correct patterns and APIs
- Matches the existing code style
- Respects security and privacy guidelines

## Best Practices

When working with this codebase:

1. **Trust the Instructions**: The instructions are curated to reflect actual project patterns
2. **Reference Examples**: Many instructions include code examples you can adapt
3. **Path-Specific > General**: Path-specific instructions take precedence over repository-wide ones
4. **Keep Updated**: Update instructions when patterns evolve

## Updating Instructions

If you notice patterns that should be documented or existing instructions that are outdated:

1. Update the relevant `.md` file
2. Keep instructions concise and actionable
3. Include code examples where helpful
4. Ensure YAML frontmatter is correct (for path-specific files)

## Format

### Repository-Wide File Format

```markdown
---
description: 'Brief description of the instructions'
---

# Title

## Section

Content...
```

### Path-Specific File Format

```markdown
---
description: 'Brief description'
applyTo: 'path/to/files/**/*.swift'
---

# Title

## Section

Content...
```

## Learn More

- [GitHub Copilot Custom Instructions Documentation](https://docs.github.com/en/copilot/customizing-copilot/adding-custom-instructions-for-github-copilot)
- [Awesome Copilot Repository](https://github.com/github/awesome-copilot)
- [Best Practices for Copilot Instructions](https://github.blog/ai-and-ml/unlocking-the-full-power-of-copilot-code-review-master-your-instructions-files/)
