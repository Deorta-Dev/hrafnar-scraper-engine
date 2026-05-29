# 🤖 Hrafnar Scraper Engine — Remote Scraping & Automation API

A NestJS backend that exposes a REST API for controlling a Playwright/Chromium instance via JSON instruction sets. Send arrays of instructions, intercept network responses, control execution flow with labels and jumps, and receive structured output via a `project` template.

---

## 🚀 Quick Start

```bash
# Install dependencies
npm install

# Install Chromium browser (required once)
npx playwright install chromium

# Start in development mode (watch)
npm run start:dev

# Build for production
npm run build && npm run start:prod
```

Server starts at **http://localhost:3000**

---

## 🌐 REST API

### `POST /session`  — Create persistent session
```json
{ "status": "success", "data": { "sessionId": "uuid-v4" } }
```

### `POST /execute` — Run instructions
```json
{
  "sessionId": "optional-uuid",
  "instructions": [],
  "project": { "output": "$scopeVar" },
  "closeSession": false
}
```

### `DELETE /session/:id` — Destroy session

---

## 🔧 Variable Resolution

Any string starting with `$` is resolved from the scope using lodash dot-paths:

```json
// scope = { user: { name: "Juan" }, token: "abc" }
// project template:
{ "name": "$user.name", "auth": "$token" }
// result:
{ "name": "Juan", "auth": "abc" }
```

Works inside ALL instruction field values too.

---

## 📖 Instruction Reference

### DOM: `goto` `click` `fill` `wait`
```json
{ "type": "goto", "url": "https://example.com", "waitUntil": "networkidle" }
{ "type": "click", "selector": "#btn", "optional": true }
{ "type": "fill", "selector": "input[name=email]", "value": "$user.email" }
{ "type": "wait", "time": 2000 }
```

### Control Flow: `label` `jump` `if`
```json
{ "type": "label", "name": "retry-start" }
{ "type": "jump", "to": "retry-start" }
{
  "type": "if",
  "condition": { "type": "elementExists", "selector": ".error-msg" },
  "jumpTo": "handle-error"
}
{
  "type": "if",
  "condition": { "type": "scopeEvaluate", "left": "$retries", "operator": ">=", "right": 3 },
  "jumpTo": "give-up"
}
```

### State & Network: `set` `listenAndTrigger` `waitForListeners`
```json
{ "type": "set", "fields": { "retryCount": 0 } }
{
  "type": "listenAndTrigger",
  "listen": { "urlPattern": "/api/auth/login", "extractKey": "data.token" },
  "trigger": { "type": "click", "selector": "#submit" },
  "saveAs": "authToken",
  "timeout": 10000
}
{ "type": "waitForListeners", "keys": ["authToken"], "timeout": 15000 }
```

### Execute: `pageFetch` `evaluate`
```json
{ "type": "pageFetch", "url": "/api/profile", "saveAs": "profile" }
{
  "type": "evaluate",
  "script": "() => document.title",
  "saveAs": "pageTitle"
}
```

---

## 🧪 Tests

```bash
npm test          # run all unit tests
npm run test:cov  # with coverage
```

**21 tests** covering ScopeManager (variable resolution, merging, hasKeys) and ExecutionEngine (all instruction types, jump/label flow, conditional jumps, error cases).

---

## ⚙️ Env & Production Notes

- `PORT` (default: 3000)
- Add an auth middleware — no built-in authentication
- For scaling: replace `Map<sessionId, SessionData>` with Redis + `playwright.connect()` remote browser
- Each session holds a full Chromium context — add idle TTL cleanup for production
