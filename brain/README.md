# My second brain

AI agents working on my projects, and everything they know, kept as plain Markdown notes that any agent can read and I can read anywhere. It was started on {KIT_DATE} from a starter kit made from Matt's brain, and it has three parts:

- **[The core](CLAUDE.md):** the one page every agent reads: what the brain is, guide mode, my defaults and the few gates (money, secrets, the sign-off, my voice).
- **[The skills](skills/README.md):** how to do things, one folder per skill: 63 to start, and more whenever a job needs one.
- **[The knowledge library](knowledge/README.md):** what the brain knows, on shelves: tasks, ventures, areas, decisions, people, systems, ideas and subjects. Every note starts with a one-line card saying what's in it and when to read it.

## What waits on me
The **[tasks index](knowledge/tasks/README.md)** is the "now" page: everything in flight, with what waits on me at the top.

## Seeing it
- **Obsidian:** this repo is a vault on my PC, in `C:\AI-Brain-Link`, and its graph draws every link between notes ([setup and how to read it](knowledge/systems/obsidian-setup.md)).
- **The brain graph:** the brain icon in Obsidian's left ribbon replays the brain growing from its git history ([how to read it](knowledge/systems/brain-graph.md)).

## Working with it
- **Start a session** at [claude.ai/code](https://claude.ai/code) with this repo selected, one session per job. Agents check a plan with me before bigger jobs (guide mode).
- **My PC:** agents run jobs on it through a GitHub Actions runner whenever it's on ([the PC](knowledge/systems/my-pc.md)). The "AI Brain Link - live jobs" window on my desktop shows what's running.
- **Giving it files:** I drag files or folders onto the "Upload point" window on my desktop, or right-click them and pick Send to, then My brain, and tell the agent what to do with them. What's waiting is listed in [the upload point](knowledge/systems/upload-point.md).
- **Brain updates:** Matt sends fixes and new parts from AnIdeaLab. The weekly tidy-up tells me what each one does, and applies it only if I say go ([brain updates](knowledge/systems/brain-updates/README.md)).
- **Keys** for services go in this repo's Actions secrets, never in a chat: the agent gives me one command to paste, which opens the page that makes the key and saves it there ([keys and accounts](knowledge/systems/keys-and-accounts.md)).
