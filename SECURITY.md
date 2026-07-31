# Security Policy

## Reporting a Vulnerability

If you find a security vulnerability in TruthLens India, please report it privately — **do not open a public GitHub issue or discussion** for it.

Email **pushprajsingh2007prashant@gmail.com** with:

- A description of the vulnerability and its potential impact
- Steps to reproduce it (proof-of-concept code/requests are welcome)
- The affected component (Flutter app, Python ingestion pipeline, `api_server.py`, Supabase schema/RLS, GitHub Actions workflows, etc.)

Please give us a reasonable window to investigate and ship a fix before disclosing publicly.

## Response Time

This is a small/solo-maintained project — reports are handled best-effort, not against a contractual SLA:

- **Acknowledgement**: within ~5 business days of your report.
- **Fix or mitigation**: timeline communicated once the report is triaged, prioritized by severity and exploitability.

## Supported Versions

Only the latest tagged release and the `main` branch receive security fixes. There is no long-term-support branch — older tagged releases are not patched; upgrade to the latest release if you're affected.

| Version | Supported |
|---|---|
| Latest release (see [Releases](https://github.com/begoneeraj/Newsup/releases)) | ✅ |
| `main` branch | ✅ |
| Older tagged releases | ❌ |
