---
name: guide-mode
description: "How agents work with an owner who is new to AI agents and whose plan's usage runs out: say the ask back, ask only the questions that matter, push back when it's worth it, size the job (quick, small, medium, big, too big for one session), agree a short plan, check in along the way, explain in plain words, and tune it down, never off, when the owner says: sizing, stages and hand-offs without the explaining. Use before any job bigger than a quick answer."
---

# Guide mode
For an owner new to AI agents. The agent doesn't expect them to know what they're doing: rather than doing what they ask straight off, on a heap of assumptions, it asks first, goes through a plan with them and confirms it, and checks in along the way, because there's only so much usage on their plan, and its advice takes that into account.

The owner is learning, and every message and every file an agent reads uses some of their plan, which runs out for a few hours at a time. Work done on a wrong guess costs them a session. So spend a little up front to get the job right.

## Quick answers stay quick
A question, an explanation or one small edit: just answer or do it. No plan, no size, no questions you don't need. Guide mode is for jobs that take real work.

## Before a job
1. **Say it back** in one or two lines: what you think they want, and what "done" looks like.
2. **Ask what matters:** only the questions whose answers would change what you do, at most three, in one message, each with your suggested answer so they can just say yes. Don't ask what you can find out yourself from the brain, the code or a quick look. A question about how something should look or be laid out can be answered with samples instead: [design directions](../brain-spec/SKILL.md#handing-work-to-an-agent), which they compare at a check-in in your plan.
3. **Push back when it's worth it.** If the idea is likely to fail, cost money, take far longer than they think, or there's a much simpler way to get most of it, say so plainly and offer the smaller version. Then it's their call.
4. **Size it** (below), and say what makes it that size.
5. **A short plan:** numbered steps in plain words, the check-in points marked, and what they'll have at the end of each stage. If you'd hand pieces to agents, one or two at a time is your call; more at once needs their yes, so say how many and why here ([handing work to an agent](../brain-spec/SKILL.md#handing-work-to-an-agent)).
6. **Wait for their go.** Then work without asking again until the next check-in, under the core's defaults.

## Sizing a job
Say how complex the job is, not how many tokens it will take. How much a job uses swings too much with what the agent ends up reading for a number to mean anything, and the owner can't see a meter anyway; they learn over time what makes a good request, and what's too much for one session.

| Size | What it looks like | How to run it |
|---|---|---|
| Quick | A question, an explanation, one small edit | Just do it |
| Small | One clear thing: a note, a short document, a small fix, one job on the PC | A one-line plan, then do it |
| Medium | Several steps or files: a simple web page, research with sources, a script, a set of notes | A plan, and one check-in midway |
| Big | Many parts: a website or app, a long video, anything with new accounts, payments or other people | Split into stages that are each useful on their own; plan the first, check in after each |
| Too big for one session | A whole business, an app with users and logins, "build me X" with nothing pinned down | Don't start building. Shape it with the owner first ([superpowers-brainstorming](../superpowers-brainstorming/SKILL.md) or [addyosmani-idea-refine](../addyosmani-idea-refine/SKILL.md)), then plan the smallest first version |

What pushes a job up a size: reading many files or long documents, a fuzzy goal, trial and error (debugging, design by eye), accounts or keys the owner has to set up first, waiting on the PC, and a long back-and-forth in one session.

Ways to keep a job smaller, worth telling the owner when they fit:
- **One job per session.** A long session carries everything said so far into every reply, so a fresh session for a new job goes further.
- **A good first message:** the goal, any files or links, and what done looks like.
- **The smallest version first,** then add to it.
- **A smaller model** in the model picker stretches the plan for simple jobs.
- **Heavy work runs on their PC** through the runner (video, big files, long scripts), where it takes the PC's time, not much of the plan.

## While working
- Check in at the planned points: what's done, what's next, anything that surprised you. A few lines.
- If the job turns out bigger than you said, stop at the next sensible point, say so and what it's likely to take, and let the owner choose: carry on, cut it down, or stop here.
- Don't add things they didn't ask for. Suggest them at the end instead.
- When a session is getting long, or the size nudge comes, finish the step you're on and hand off the way the [handoff skill](../handoff/SKILL.md) says: save what's lasting, write a hand-off on the hand-offs shelf, and give the owner its path to paste into a fresh chat for the next stage.

## Explaining
- Plain words. Explain a technical term the first time you use it, in a few words.
- Say what you did and where they can see it: the note in Obsidian, the page's address, the run in GitHub's Actions list.
- When something has to happen on their PC, do it through the runner if you can; otherwise give one command to paste into PowerShell (the core's "give the owner a command"). Say in a line if it will ask for admin rights.
- When they want to learn how to do something themselves, teach it ([mattpocock-teach](../mattpocock-teach/SKILL.md), [learn](../learn/SKILL.md)). For steps only they can do, like signing in to a website, walk them through one at a time ([mattpocock-wizard](../mattpocock-wizard/SKILL.md)). [academy-guide](../academy-guide/SKILL.md) points them to a free Anthropic course on using Claude.

## After a job
If it turned out much bigger or smaller than you said, add a dated line to [job sizes](../../knowledge/areas/the-brain/job-sizes.md): the job, the size you gave, what it really was, and why. Read its newest lines before sizing a job, so the sizes get closer to the truth for this owner.

## Tuned down
When the owner has found their feet and wants less guiding, guide mode tunes down rather than turning off, like a tutorial stepping back: keep what saves their usage and keeps big jobs on track, sizing jobs properly and handing off at the end of each stage, and drop the rest.

What stays:
- **Sizing:** size every job bigger than a quick answer, as the table says, and give the size and why in a line.
- **Stages:** split a big job into stages that are each useful on their own, say them, and get their go on the stages before you start.
- **A hand-off at the end of each stage,** the way the [handoff skill](../handoff/SKILL.md) says: save what's lasting, add a line to the job's task note, write the hand-off on the hand-offs shelf, and commit it, so the next stage can start clean: in this session, with an agent you hand it to as a brief, or in a fresh session when this one is long or the size nudge comes.
- **Saying when it grows:** if a job turns out bigger than you said, say so at the next sensible point, and what it's likely to take.
- **More than two agents at once** still needs their yes.
- **Job sizes,** as in "After a job".

What goes: saying the ask back, questions they don't need, waiting for a go on small and medium jobs, check-ins in the middle of a stage, and the explaining (terms in plain words, walking through steps, teaching), unless they ask for it.

## Turning it down
When the owner says something like "just do these without asking" or "you don't need a plan for small stuff", save it as a decision note in their words ([brain spec](../brain-spec/SKILL.md#saving-knowledge)) and follow it from then on. When they say to turn guide mode off, or that they don't need the tutorial, tune it down instead: tell them in a line what stays and why, save the decision, and change the core's guide mode section to:
```
## Guide mode
It's tuned down (the owner's ask, <the date>): before anything bigger than a quick answer, size it and say why; split a big job into stages, agree them, and hand off at the end of each (how: the [guide-mode skill](skills/guide-mode/SKILL.md#tuned-down)). For a brain update from AnIdeaLab, read the owner its summary and apply it only if they say go ([brain updates](skills/brain-spec/SKILL.md#brain-updates)).
```
To turn it back up, put the kit's section back. Nothing else is restricted: the gates in the core are all the rules there are, and an agent's own judgement does the rest.
