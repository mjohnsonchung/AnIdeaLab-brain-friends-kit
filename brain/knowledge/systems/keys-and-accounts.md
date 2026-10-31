---
about: "The outside accounts and keys the brain uses, by name only, and how the owner adds a key. Read before using, connecting or closing an account, or when a job needs a key."
tags: [the-brain]
updated: {KIT_DATE}
---
# Keys and accounts

The accounts the brain uses and the keys agents reach them with, by name only. Keys and passwords never go here, in any file, or in a chat (the secrets gate in the [core](../../CLAUDE.md)). When an account or key is added or closed, change its row.

## Adding a key
When a job needs a key (an API key for a service), the agent gives the owner one command to paste into PowerShell, which opens the page that makes the key, reads it in hidden, checks it and saves it in this repo's GitHub Actions secrets ([add-a-key](../../skills/add-a-key/SKILL.md)). Then the agent adds its row below. By hand instead, the agent says which service, where to get the key, and the name to save it under, in capitals with underscores, like `OPENAI_API_KEY`, and the owner:
1. **On GitHub:** opens this brain's repo, then Settings, then Secrets and variables, then Actions, then New repository secret; types the name, pastes the key, and saves. Jobs that run through GitHub Actions, the PC runner's included, can use it from then on. This is the key's home.
2. **In Claude, if a session needs it directly** (optional): the environment menu in the session's title bar, then Edit, then the secrets or environment variables section, with the same name. A new session picks it up.

A website's own keys go in its host's settings (Vercel, Cloudflare and so on), where the site reads them.

## Accounts
| Service | Account | Since | Used for |
|---|---|---|---|
| GitHub | the owner's | {KIT_DATE} | This brain's private repo, and the PC runner |
| GitHub | Matt's testing account, `diagnostics-anidealab`, as a collaborator on this repo | {KIT_DATE} | Matt, who made the kit, can see this brain and copy it to test the kit while it's in testing; the installer invited the account, and GitHub lets a collaborator change the brain too. The owner can take it off in the repo's Settings, Collaborators |
| Claude | the owner's | {KIT_DATE} | The agents |

## Keys
| Name (GitHub secret) | Service | Since | Used for |
|---|---|---|---|
