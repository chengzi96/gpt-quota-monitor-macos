# Third-party notices

## OpenAI Codex App Server

GPT流量监控 uses the standalone **OpenAI Codex App Server** for the official ChatGPT browser login flow and `account/rateLimits/read` quota retrieval.

- Version: `0.151.0`
- Platform: `aarch64-apple-darwin`
- Release tag: `rust-v0.151.0`
- SHA-256: `09193ef452f35d3558ac5bef21e14d6e3c9763edaa36e6c614126a15fca0ff57`
- Upstream: https://github.com/openai/codex
- License: Apache License 2.0 — https://github.com/openai/codex/blob/main/LICENSE

The component is **not stored in this repository**. The build script downloads the official release asset directly from OpenAI and verifies the pinned SHA-256 before use.

GPT流量监控 does not bundle the full Codex CLI and does not use Codex code-generation, shell execution, or workspace capabilities.

## Reference

Early field-mapping and window-classification research referenced Token Monitor:

- https://github.com/Javis603/token-monitor — MIT License

The SwiftUI application in this repository is an independent implementation and does not copy Token Monitor's Electron UI source code.
