---
about: "The brain graph, the Obsidian view that replays the brain's growth from git history: opening it, reading it, its settings, and the rules for changing it. Read before touching its plugin or explaining it."
tags: [the-brain]
updated: {KIT_DATE}
---
# The brain graph

A view inside Obsidian that shows the brain growing, built in Matt's brain (from 11 Oct 2026) and carried over with the kit. Every folder with more than one note is a circle, every note is a dot that appears when it was written, and every link is a line that forms when it was made. It all comes from the repo's git history, so agents don't log anything extra for it. This brain's history starts on {KIT_DATE}, so its graph grows from the first day.

## Opening it
- On the PC, click the brain icon in Obsidian's left ribbon, or press Ctrl+P and run "Brain graph: Open brain graph".
- The first time, run "Reload app without saving" once from Ctrl+P. If it still doesn't show, switch on "Brain graph" under Settings, then Community plugins.
- It needs Git on the computer, and doesn't run on a phone.

## Reading it
- **Dots are notes, circles are folders.** The core sits in the middle; the skills and knowledge libraries are the two big branches. Bigger dots have more links.
- **Lines are links,** bundled along the branches, faint until you point at a note.
- **The accent colour is activity:** a new note sends out a ring, a new link flashes, and an edited note pulses. The owner's own edits from Obsidian show in a second colour.
- **The timeline box,** bottom centre, shows the commit the replay is on and a smoothed curve of how busy each commit was.

## Using it
- **Play** with the round button or the space bar. Drag along the curve, scroll over it or use the arrow keys to move through commits; the list button opens every commit.
- **Point at a dot** to see its links; click it to open the note. Drag a dot and its circle follows (physics on).
- **Zoom** with the scroll wheel; double-click or press F to recentre.
- **Live:** while it's open it checks for new commits every 15 seconds and plays them in.
- **Settings** (the sliders button, top right): theme, accent colour, speed, where the replay starts, and what to show. They save to `.obsidian/plugins/brain-graph/data.json`.
- **A fresh start:** a commit whose message starts with "Fresh start" makes the replay begin there, with everything before it already in place.

## For agents
- The code is `.obsidian/plugins/brain-graph/main.js`, with its look in `styles.css`. Don't change it unless the owner asks.
- `test/run.mjs` runs it in Chromium with a stand-in for Obsidian, against this repo's history, and takes screenshots: `node .obsidian/plugins/brain-graph/test/run.mjs .obsidian/plugins/brain-graph/main.js <scratch folder>` (it needs Playwright).
