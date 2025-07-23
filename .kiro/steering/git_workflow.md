---
inclusion: always
---

# Development Workflow Guidelines

## Branch Management
- Create feature branches from `main` using descriptive names: `feature/device-discovery`, `fix/network-timeout`, `docs/protocol-reference`
- Keep branches focused on single features or fixes
- Always work in feature branches, never commit directly to `main`

## Commit Standards
- Use conventional commit format: `type(scope): description`
- Required types: `feat`, `fix`, `docs`, `test`, `refactor`, `chore`
- Examples: `feat(device): add USB device enumeration`, `fix(network): handle connection timeouts`
- Make atomic commits at logical completion points
- Ensure each commit builds successfully with `swift build`

## Validation Requirements
- Run `swift test` before committing to verify functionality
- Validate code style compliance (SwiftLint runs in CI)
- Include unit tests for all new functionality
- Document public APIs using Swift documentation comments (`///`)

## Implementation Workflow
- Break complex features into incremental commits that build successfully
- Test changes locally before committing
- Create pull requests for feature completion
- Follow Swift API Design Guidelines and existing project patterns