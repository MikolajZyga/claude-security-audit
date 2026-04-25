<!-- BEGIN security-audit rules — do not edit between markers -->
## Security rules (enforced every session)

- Never hardcode secrets, API keys, tokens, passwords, or DB URLs with credentials. Read them from env vars (`process.env.X`, `import.meta.env.X`, `os.environ["X"]`, etc. — see `references/frameworks.md` if installed).
- Never put server-only secrets behind a public-prefixed env var (`NEXT_PUBLIC_*`, `VITE_*`, `REACT_APP_*`, `EXPO_PUBLIC_*`). Those are bundled into the client.
- Never commit `.env*` files except `.env.example`. Use `.env.local` for real values.
- Never log, `console.log`, `print`, or echo a token, secret, password, or auth header — even temporarily during debugging.
- Never paste a real secret into chat, commit messages, or comments. If a value is needed for context, refer to it as `<file>:<line>` only.
- Before suggesting `git commit` or `git push`, ensure the security-audit skill has been run this session, or run it now.
- If a secret was already pushed to a remote, the only real fix is to **rotate the key at the provider**. History rewrite alone does not undo a leak.
<!-- END security-audit rules -->
