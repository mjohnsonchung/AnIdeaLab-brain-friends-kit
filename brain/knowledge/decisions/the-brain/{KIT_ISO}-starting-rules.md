---
about: "The rules this brain started with, from Matt's brain: the owner's defaults, the gates, guide mode, and what was left out and why. Read before changing a default or a gate, or to see where a rule came from."
tags: [the-brain]
status: current
updated: {KIT_DATE}
---
# The rules this brain started with

**Decided** {KIT_DATE}, by Matt, who made the starter kit this brain was started from, in a Claude Code session in his own brain. They're a starting point: the owner can change any of them, and their own decisions win.

## Where they came from
Matt runs his own second brain: AI agents working on his businesses, with a core every agent reads and two libraries. He made this kit so friends could start one the same way, with "a little bit, not more restrictions necessarily, but our one's intentionally more stripped back and free than theirs would be". He asked for the same structure and rules where they help, without being "overly constraining".

## Kept from Matt's brain
- **Rules about how are defaults** (Matt, 16 Oct 2026): the agent picks the host, tool, service or format, and says why when it changes one.
- **Reuse before you build** (17 Oct 2026): use existing code, say what was used, and ask before GPL or AGPL code goes into anything sold.
- **PC work goes to the PC,** through a GitHub Actions runner (17 Oct 2026), so needing a GPU or the owner's apps never rules a route out.
- **Give the owner a command** (22 Oct 2026). Matt: "just give me a powershell command to run. also, make that the default option for tasks like this that involve my computer". He asked for the same here: a task on the owner's computer runs through the runner, or as one command to paste, before click-by-click steps.
- **Not tied to one AI provider** (18 Oct 2026): plain Markdown, relative links and plain scripts.
- **No Claude artifacts** (24 Oct 2026). Matt: "if you're going to refer to a Claude artifact or any other kind of AI artifact, that wouldn't exist to an separate agent in the GitHub repo. Or with access to my computer... That agent would still be able to get it. So no Claude artifacts. Anymore." He wanted the same here. So what the brain saves or points to lives in its repo, on the owner's PC or in another place any agent can reach, and a page for the owner is an HTML file saved there.
- **Ship it yourself** (16 Oct 2026): push and publish when a change works; git history is the safeguard. Here it starts once the owner has said go.
- **One check is enough** (20 Oct 2026). Matt: "We just need a quality check most of the time, just one, if that... for like complex tasks, then obviously, yeah. Can do with more checks", "no matter what a tool or mode suggests". For this kit he called it "the new kind of decision that one review is enough unless it's for extremely complex tasks".
- **The gates:** money (spending needs the owner's go; agents never pay or refund), secrets (keys only in GitHub's Actions secrets or a host's secret settings, never in files or chat), the sign-off on outside messages ("Assistant built by AnIdeaLab.com", never on replies to the owner; Matt: "keep the sign off on outside messages", and on 23 Oct 2026 he called it the owner's return for "their free use of the brain and the research that went into making it"), and the owner's voice (never answer for them).
- **Commit straight to main,** small commits, never force-push.

## Added for this brain
- **Guide mode** (Matt, 22 Oct 2026): "somewhat of like a beginner mode... the conversation wouldn't expect that they know what they're doing", with plans confirmed before work and check-ins along the way, "because there's only so much usage that the person gets". Jobs are sized by complexity, not tokens: if estimates were "going to be like wildly off... it's not worth even including, they're just going to have to figure out over time like what makes a good prompt". The [guide-mode skill](../../../skills/guide-mode/SKILL.md) has the how.
- **Best guess, light checks** (Matt, 24 Oct 2026). On a game he was building: "best guess 2 pass kinda thing, not toooo much verifying, ill do that after when playing". He wanted the same here, "but just a minimumal amount of checks/verifying needed for the task at hand". The two passes, a best-guess go and then one fix-up pass, are the agent's reading of "2 pass". It sits alongside "one check is enough".
- **One agent at a time** (Matt, 24 Oct 2026): "agents should only run on one thread, even for like a complex task. Like they can spawn one agent and it can run to completion, and then they can spawn another agent", because "splitting up complex tasks like that is definitely useful between agents memory wise", but not "multiple agents, having them all work in parallel. It's just for usage, consumption, and yeah, it's just better for users. At least for now." It's a default: "the person whose brain it is could do that", change it. Matt's own brain allows a few agents at once.
- **60 general skills,** and the way to get more (Matt: "just give them general basic skills. They can decide which ones they want further than that. But give them the way to get good quality skills that we've done"): the [find-skills skill](../../../skills/find-skills/SKILL.md).

## Left out on purpose
- Matt's own notes, people, projects and tasks.
- Matt's looser rules for his own brain: no rules about personal information, few gates on what the brain makes, says and offers, and legal work being the agent's call. They suit him ("we're quite lax on legal stuff specifically, because, you know, I'm a lawyer"). This brain runs on the agent's own normal judgement for those, with nothing added either way (Matt: "just the default kind of setting. You don't have to build anything extra in").
- Matt's own names (Farm Town, his ventures, his PC's name).
