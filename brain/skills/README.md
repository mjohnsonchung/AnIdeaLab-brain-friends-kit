# Skills

How to do things. Every skill, the brain's own and copied, has a line in a list by topic, one line per skill, so open the list your job falls under, then the skill. Any agent, Claude Code included, reads this and opens the `SKILL.md` it needs, so keep it short: a new skill gets a line in a list, and only one most jobs need goes here too. How a skill is shaped and when to write one: the [brain spec](brain-spec/SKILL.md#a-skill). To find and add more: [find-skills](find-skills/SKILL.md).

**The two kinds.** In each list the brain's own come first, under "The brain's own": written for this brain, and changed freely. Any skill can have a `LESSONS.md` beside it: what agents learned using it here ([how skills learn](brain-spec/SKILL.md#how-skills-learn)). The rest are copied and kept as they came, and [lists/sources.md](lists/sources.md) names each with its source, commit and licence. That list is how the scripts tell the two kinds apart: a skill with a line in it is copied, and any other is the brain's own.

## The main ones
- [brain-spec](brain-spec/SKILL.md): where each kind of thing goes in the brain and what shape it takes, and how to apply a brain update from AnIdeaLab.
- [guide-mode](guide-mode/SKILL.md): how to work with an owner new to AI agents: say the ask back, size it, agree a plan, check in.
- [my-pc](my-pc/SKILL.md): run commands and jobs on the owner's PC through the `my-pc` runner, and check or fix its setup.
- [find-skills](find-skills/SKILL.md): find a good skill from outside the brain, copy it in, and keep copied skills up to date.

## The lists by topic
- [The brain and your PC](lists/the-brain.md): the first session, guide mode, the brain spec, the weekly tidy-up and the PC runner.
- [Planning, thinking and learning](lists/planning.md): shaping an idea, planning a change, specs, and learning a topic.
- [Building and fixing code](lists/code.md): building, testing, debugging, reviewing and shipping code.
- [Websites and design](lists/web-and-design.md): how a site looks, its words, testing it, and putting it live.
- [AI, Claude and skills](lists/ai-and-claude.md): finding and making skills, building on Claude, MCP servers, and writing for agents.
- [Obsidian](lists/obsidian.md): Obsidian's Markdown, bases, canvases, and web pages into notes.
- [Business, marketing and money](lists/business.md): marketing, customers, prices, proposals, invoices, data and sums.
- [Life admin](lists/life-admin.md): planning an event.

A Claude session also has Anthropic's own skills for Word, PDF, Excel and PowerPoint files, deep research and a few more, without copies here.

## How the copied ones are kept
Kept as they came, from Anthropic first, then the companies behind the tools, then very popular collections. All are under the MIT or Apache 2.0 licence. What was changed, and nothing else: each folder's name (an Anthropic plugin's skill is `<plugin>-<skill>`, another source's `<source>-<skill>`), its `name:` line to match, and links to shared files, which are in [anthropic-plugins/](anthropic-plugins/) (Anthropic's plugins' notes and licences) and [sources/](sources/) (each other source's README and licence). Where a copied skill names a sibling as `superpowers:<name>`, the brain's copy is `superpowers-<name>`, and the same for the other sets. In Matt Pocock's skills, "Matt" means Matt Pocock. Where one asks for more reviewers, tests or checks than the core's "best guess, light checks" and "one check is enough", or for agents running side by side against its "one agent at a time", the core wins. An email, reply, letter or other message a skill drafts for someone outside the brain ends with the core's sign-off, whatever the skill's own template says.

## Claude-only parts, and the plain way
Some of these skills were written for Claude's apps. Any agent can do the same with these swaps.

| When a skill says | Do this instead |
|---|---|
| Render or publish an artifact | Write the HTML file, save it where any agent can get it, and open it in a browser or send it to the owner. Never a Claude artifact |
| Connectors, or "suggest a connector" | Use whatever tool you have for that app, and tell the owner in words which app to connect |
| Ask with choice cards | Ask in plain text, with numbered options |
| Spawn subagents | Do the steps yourself, one after another |
| Set up a scheduled task | A row in [routines](../knowledge/systems/routines.md); a scheduled AI job needs the owner's yes |
| Claude's memory, a `CLAUDE.md` memory or `TASKS.md` | The brain's own notes: the [knowledge library](../knowledge/README.md), with tasks on its tasks shelf |
| Claude in Chrome, the built-in browser, computer use | Your own browser or desktop tool, or a job on the owner's PC ([my-pc](my-pc/SKILL.md)) |
