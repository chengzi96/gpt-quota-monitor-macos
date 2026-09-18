# Privacy

GPT流量监控 is designed to read quota information with the smallest practical data surface.

## What the app reads

- Account/rate-limit information returned by the standalone OpenAI Codex App Server.
- The connected account's plan label and email address when OpenAI's component returns them, for connection status display.
- Local app settings, local quota history, and local runtime diagnostics.

## What the app does not read

- Chat conversations or prompts.
- Browser cookies or webpage DOM.
- ChatGPT access tokens or refresh tokens.
- Source code, local projects, or Codex workspaces.

Authentication, credential storage, callback handling, and token refresh are owned by the official OpenAI Codex component. GPT流量监控 communicates with that component through its app-server protocol and does not intentionally persist raw authentication credentials.

## Local files

Quota history and runtime diagnostics stay on the Mac. Runtime diagnostics record lifecycle events such as app start, refresh start/success/failure, and app-server start/stop. They intentionally exclude account identifiers, tokens, prompts, code, and RPC payload contents.

## Network access

The public-source build downloads the pinned OpenAI Codex App Server once from OpenAI's official GitHub release and verifies its SHA-256. Runtime quota/authentication network traffic is performed by the OpenAI component.

## Unofficial project

GPT流量监控 is an independent community project and is not an official OpenAI product.
