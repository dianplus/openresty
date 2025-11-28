# Cursor Rules Guide

This document provides detailed guidance on the project's rule system. For a quick reference, see `AGENT.mdc`.

## Rule Source Reference

This project's rule system is based on the [AI Coding Rules](https://github.com/maskshell/ai-coding-rules) framework, which provides:

- **Layered Rule Management**: IDE layer (general) → Language layer → Framework layer → Project layer (specific)
- **Dual-Track System**: Concise rules for daily use and full rules for learning
- **Meta-Rules**: Rules for writing rules to help AI generate new rule types reliably

## IDE Layer Rules Guideline

### Global IDE Rules

IDE layer rules should be installed in the global Cursor configuration directory (`~/.cursor/rules/`) to apply to all projects:

```bash
# Install IDE layer rules (concise version recommended)
mkdir -p ~/.cursor/rules
cp /path/to/ai-coding-rules/.concise-rules/ide-layer/* ~/.cursor/rules/
```

### Project-Specific Rules

Project-specific rules are stored in `.cursor/rules/` (this directory) and apply only to the current project:

- **Priority**: Project rules override IDE layer rules
- **Organization**: Rules are organized by category (Python, Shell, etc.)
- **Naming**: Use numbered prefixes (01-, 02-, etc.) for ordering

### Rule Hierarchy

1. **IDE Layer** (`~/.cursor/rules/`) - Most general, applies to all projects
2. **Project Layer** (`.cursor/rules/`) - Project-specific, overrides IDE layer rules

For more details, see the [AI Coding Rules documentation](https://github.com/maskshell/ai-coding-rules).

## Rule Categories

### Python Rules

> **Note**: These rules are copied from the [AI Coding Rules](https://github.com/maskshell/ai-coding-rules) reference project.

- **01 · Python Fundamentals**: `.cursor/rules/01-python-basics.mdc`
  - Core Python typing rules, Pydantic usage basics, and annotation requirements.
- **02 · FastAPI & Pydantic Schema**: `.cursor/rules/02-fastapi-schema.mdc`
  - Detailed schema design guidelines, request/response separation, and validation rules for FastAPI services.

### Shell Scripting Rules

> **Note**: These rules are copied from the [AI Coding Rules](https://github.com/maskshell/ai-coding-rules) reference project.

- **01 · Shell Scripting Basics**: `.cursor/rules/01-shell-basics.mdc`
  - Basic shell scripting standards and best practices.
- **02 · Shell Scripting Advanced**: `.cursor/rules/02-shell-advanced.mdc`
  - Advanced shell scripting patterns and techniques.
- **03 · Shell Scripting Compatibility**: `.cursor/rules/03-shell-compatibility.mdc`
  - Cross-platform compatibility guidelines for shell scripts.

## Adding New Rules

Add new `.mdc` files to `.cursor/rules/` and reference them in `AGENT.mdc` when additional rule sets are introduced.
