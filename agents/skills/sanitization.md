# Sanitisation

Read this before committing documentation, configuration, or any file that could
carry this machine's identity into the repository. This repo is public.

The rule itself lives in the user's global instructions (`~/.ante/skills/writing-docs`);
this guide is the procedure that enforces it here.

## Run the check

```bash
scripts/check-sanitized.py
```

Exit 1 means something was found. It prints `path:line: label` and never echoes
the value, so a hit can be looked up without copying a secret into a terminal
scrollback or a chat log.

It reads tracked files **plus** anything new that git does not ignore, because
the file being added is the one nobody has reviewed yet.

## What it looks for

- Credential shapes: GitHub tokens, `sk-` API keys, AWS access keys, Slack
  tokens, private key blocks, JWTs.
- A credential-shaped name (`api_key`, `secret`, `token`, `password`,
  `access_key`) assigned a literal 24+ character value. Variables,
  placeholders, and redactions are not flagged.
- Proxy subscription links — the node configs themselves stay out via
  `.gitignore`, but a link pasted into a doc does not.
- In this machine's own configuration (`docs/`, `local-config/`, `niri-config/`,
  `etc/`, `agents/`): a real home directory other than a placeholder, and LAN
  addresses.

## What it does not look for, on purpose

Test fixtures invent users (`alice`, `dhh`, `storage-target`) and documentation
explains addresses (`192.168.1.50` for a printer). Flagging those produced 198
findings on the first run, and a check that noisy gets piped to `cat` — worse
than having none. So the identifier rules apply only where a real value would be
consulted, and `manual/` is out of scope entirely.

Docker's own defaults (`172.17.0.1` bridge, `172.18.0.1` compose) are excluded
too: they are identical on every machine and identify nothing.

`EXEMPT` in the script lists files held byte-identical to upstream on purpose.
`bin/omarchy-install-chromium-google-account` hardcodes a public OAuth client
secret for Chromium's device flow; rewriting an upstream file to satisfy a
linter would make the overlay patch stop replaying.

## Allowed

`jianlongliu` may appear — the user agreed to that explicitly. `~` and `$HOME`
are still preferred in paths, and `"$USER"` in commands.

## Keeping sensitive files out

`.gitignore` is the first line of defence, not the check: `.env` and `.env.*`,
`*.token`, `*.key`, `*.pem`, `*credential*`, `*secret*`, `*subscription*`,
`mihomo*.yaml`, and `*.bak*` (backups live in `~/.local/state/backups/`).
A new repo copies this baseline.

## When to run it

- Before committing anything under `docs/`, `local-config/`, `niri-config/`,
  or `etc/`, and before adding a file that quote-copies machine output.
- Before a release or a public push, over the whole tree.

It is not wired into `./test/all`: the scan is about what is staged, and a
suite that fails on committed history teaches people to ignore it.
