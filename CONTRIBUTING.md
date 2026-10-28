# Contributing to AOU-RTL

Thank you for your interest in contributing to the AXI-over-UCIe Bridge RTL project!

## How to Contribute

### Reporting Bugs

If you find a bug, please report it via [GitHub Issues](https://github.com/tenstorrent/tt-oca-harness-aou/issues):

1. Search existing issues to avoid duplicates
2. Provide a clear title and description
3. Include steps to reproduce the issue
4. Specify your environment (simulator version, OS, etc.)
5. Include relevant log files or error messages

### Submitting Changes

We welcome bug fixes, improvements, and new features via Pull Requests:

1. **Fork the repository** and create a new branch from `main`
2. **Name your branch** using one of the required prefixes:
   - `feature/` -- new functionality (e.g., `feature/add-fdi-support`)
   - `bugfix/` -- bug fixes (e.g., `bugfix/fix-clock-gating`)
   - `hotfix/` -- critical fixes (e.g., `hotfix/critical-reset`)
   - `chore/` -- maintenance tasks (e.g., `chore/update-ci`)

   A CI check ([`.github/workflows/branch-name-check.yaml`](.github/workflows/branch-name-check.yaml))
   enforces this convention; PRs from branches that do not match will
   fail the check and not be considered.
3. **Make your changes** following the coding standards below
4. **Test your changes** using the verification testbench (see Testing Requirements)
5. **Commit your changes** with clear, descriptive commit messages
6. **Submit a Pull Request** with a detailed description of your changes

### Review Process

- Pull requests are reviewed on a **weekly basis**
- Maintainers will provide feedback or request changes
- Once approved, changes will be merged to the main branch

## Coding Standards

### SystemVerilog/Verilog Code

- Follow existing code style and formatting
- Include SPDX license headers in all new files:
  ```systemverilog
  // SPDX-License-Identifier: Apache-2.0
  // SPDX-FileCopyrightText: © 2025 Your Name or Organization
  ```
- Use meaningful signal and module names
- Add comments for complex logic
- Ensure code is synthesizable unless explicitly intended for simulation only

### Documentation

- Update relevant documentation when changing functionality
- Follow the existing documentation structure
- Use clear, professional language
- Define acronyms on first use

### Testing Requirements

- A change to `RTL/`, `csr/` or the verification testbench (`hw/ip/aou/dv`) runs the full
  regression before review: `python3 scripts/regress.py --sim vcs` (or `--sim verilator`, or
  the shorthand `make regress SIM=vcs`) in `hw/ip/aou/dv`, as
  described in its README under "Run everything". The pull request states the simulator and the
  `Result:` line of the regression's `summary.md`. CI runs only the short `ci` group, so it does not
  replace this run.
- The regression must show no FAIL or XPASS that `main` does not already have. Failures caused by
  known bugs are judged XFAIL through `hw/ip/aou/dv/expected_fail.yaml`; explain any new one.
- Add new tests for new functionality
- Document test methodology in commit messages

### Commit Messages

- Use clear, descriptive commit messages
- Start with a short summary (50 chars or less)
- Provide detailed explanation in the body if needed
- Reference related issues (e.g., "Fixes #123")

## Code of Conduct

Please note that this project adheres to a [Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.

## Questions?

If you have questions about contributing, please:
- Open a [GitHub Issue](https://github.com/tenstorrent/tt-oca-harness-aou/issues) for general questions
- Contact the maintainers via the repository

## License

By contributing to this project, you agree that your contributions will be licensed under the Apache License 2.0.

---

We appreciate your contributions to making AOU-RTL better!
