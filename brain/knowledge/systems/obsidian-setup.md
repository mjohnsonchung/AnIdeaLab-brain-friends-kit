---
about: "How the owner sees and edits the brain in Obsidian on their PC: the setup, syncing with GitHub, what the map's colours and lines mean, and the shared settings agents may change. Read before touching .obsidian/ or explaining the map."
tags: [the-brain]
updated: {KIT_DATE}
---
# Obsidian: seeing the brain as a map

Every note is plain Markdown, and notes link to each other with normal relative links, which Obsidian's graph draws as lines. The repo carries the Obsidian settings (in `.obsidian/`), the same as in Matt's brain, so the map comes out coloured by shelf.

## The setup
The installer did it all: it cloned the brain into `C:\AI-Brain-Link\<repo name>`, added the Obsidian Git plugin, and opened the folder as a vault. The first time, Obsidian asks whether to trust the vault's plugins: "Trust author and enable plugins". Two plugins are on:
- **Obsidian Git** syncs: it pulls when Obsidian opens and commits and syncs every 10 minutes, so the owner's edits reach GitHub as "My edits in Obsidian" and agents' work arrives in Obsidian. It uses the GitHub sign-in the installer set up (`gh auth setup-git`). Its code isn't in the repo, so another computer installs it from Settings, then Community plugins, then Browse, "Git" by Vinzent03.
- **The brain graph** (the brain icon in the left ribbon) replays the brain's growth ([brain-graph.md](brain-graph.md)). Its code is in the repo.

Keep the brain's folder out of OneDrive, Dropbox and iCloud: two sync systems on one git folder can corrupt it.

## Reading the map
Press Ctrl+G, or click the graph icon in the left ribbon. The bookmarks panel (the bookmark icon in the left sidebar) has **Map views** ("Whole brain" and "Ventures") and **Start here** (the front door, the core, the knowledge library, the tasks, the skills list and this note). The first time the settings arrive, press Ctrl+P and run "Reload app without saving" before opening the graph.

Each dot is a note, coloured by where it lives; bigger dots have more links. The colour list is in the graph's settings under Groups.

| Colour | Notes | Folder |
|---|---|---|
| White | The core, the front door and the knowledge library's index | top level, `knowledge/README.md` |
| Sky blue | Skills | `skills/` |
| Amber | Tasks | `knowledge/tasks/` |
| Aqua | Ventures: projects and businesses | `knowledge/ventures/` |
| Lavender | Decisions | `knowledge/decisions/` |
| Silver | Areas | `knowledge/areas/` |
| Orange | People | `knowledge/people/` |
| Cobalt | Systems | `knowledge/systems/` |
| Pale coral | Ideas | `knowledge/ideas/` |
| Violet | Subjects | `knowledge/subjects/` |

- Each line is a link written in a note; zoomed in, arrows point from the note holding the link. Point at a dot to see its links; click it to open the note.
- Ctrl+P, then "Graph view: Open local graph", shows one note's neighbours.
- Notes in any `history/` folder are hidden (Settings, then Files and links, then Excluded files).
- The softer lines and clearer arrows come from the `brain-colours` snippet (Settings, then Appearance, then CSS snippets). Stay on the dark theme for the map.

## Editing in Obsidian
- The owner can read and edit any note. Obsidian is set to write the same relative links agents write, and to fix links when a note is renamed or moved.
- If the Git plugin reports a conflict (the owner and an agent changed the same lines), don't force anything: tell an agent in a session.
- Pasted images and files go in an `attachments/` folder on that computer only; the repo ignores it, because big files don't go in the brain.

## For agents
- `.obsidian/` holds the shared settings: `app.json` (hidden folders, link format), `appearance.json` (dark theme and the snippet), `graph.json` (colour groups, filter, display, forces), `bookmarks.json`, `snippets/brain-colours.css` and `plugins/obsidian-git/data.json` (sync timing and commit message). Per-device layout and plugin code are git-ignored, except the brain graph's code in `plugins/brain-graph/`.
- Colour groups are matched top to bottom, first match wins, so the white group stays last. When a shelf is added, add its group (`path:"knowledge/<shelf>/"`, colour as a decimal of 0xRRGGBB) above the white group, and to the table above.
- The owner's edits arrive on `main` as commits named "My edits in Obsidian, {date}". Pull before you start.
