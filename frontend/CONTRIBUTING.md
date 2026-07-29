# Contributing to Mobile Portainer Flutter

Thanks for your interest in contributing! 🎉

## Code of Conduct

Be respectful, constructive, and inclusive. We aim to build a welcoming community for everyone.

## How Can I Contribute?

### 🐛 Reporting Bugs

- Search the [existing issues](https://github.com/CodeFuckee/mobile_portainer_flutter_module/issues) first to avoid duplicates.
- Use the **Bug Report** template when opening a new issue.
- Include: platform, Flutter/Dart versions, steps to reproduce, screenshots, and logs.

### 💡 Suggesting Features

- Use the **Feature Request** template.
- Explain the problem you're solving, not just the solution.
- Include mockups or screenshots if relevant.

### 🔧 Code Contributions

#### Setup

```bash
git clone https://github.com/CodeFuckee/mobile_portainer_flutter_module.git
cd mobile_portainer_flutter_module
flutter pub get
```

#### Branching

Branch directly off `main`:

```bash
git checkout main
git pull origin main
git checkout -b feat/your-feature-name
```

Branch naming:
- `feat/...` — new features
- `fix/...` — bug fixes
- `docs/...` — documentation
- `refactor/...` — code restructuring

#### Development Guidelines

- **State Management**: Use `setState` only. Do not introduce third-party state management libraries (BLoC, Riverpod, Provider, etc.).
- **Platform Compatibility**: All code must work on Android, iOS, macOS, Web, and OpenHarmony. New dependencies must be verified to support OpenHarmony.
- **Analysis**: `flutter analyze` must pass with zero errors before committing.
- **Localization**: Update both `lib/l10n/app_en.arb` and `lib/l10n/app_zh.arb` for any user-facing strings.
- **Formatting**: Do not run `dart format`. Follow the existing code style.

#### Before Submitting a PR

1. Run `flutter analyze` and fix any errors.
2. Run `flutter build web` to verify web build succeeds.
3. Run `flutter test` if applicable.
4. Write a clear PR description using the PR template.

#### Code Review

All submissions require review. A maintainer will:
- Verify the change addresses the stated problem
- Check for platform compatibility
- Review code style and patterns
- Ensure tests pass in CI

### 📖 Documentation

Improvements to README, comments, and wiki are always welcome!

### ❓ Questions

For questions, please use [GitHub Discussions](https://github.com/CodeFuckee/mobile_portainer_flutter_module/discussions) rather than opening an issue.

## Project Structure

See [README.md#project-structure](README.md#-project-structure) for an overview.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
