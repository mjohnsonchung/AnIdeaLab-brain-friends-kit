---
name: handoff
description: "How any agent in this brain hands work on, in one format used three ways: a session hand-off to a fresh chat (at the end of a stage, or when the size nudge says the conversation is long), a brief to an agent, and a report back from one (at the end of its work, or at its own nudge at 450k). What goes in it, saving what's lasting first, where it goes (the hand-offs shelf), what to do at the nudge, how to start from a hand-off, doing it by hand where no hook runs, and the nudge's settings. Use whenever you hand off, brief an agent, report back, get the nudge, or are given a hand-off's path."
---

# Hand-offs
Matt, whose brain this one was started from, built this in his own brain first, on 1 Nov 2026: "a proper handoff mechanism that can be reused and called upon by agents and sub-agents for how to handle work. And then also... a way that the coordinator would always be saving those handoffs in an efficient way into the brain so that it can call upon that or any future session." On what goes in one: "one format used, three ways... But also needs to tell them where it is."

**Why it matters.** Everything said in a conversation is read again on every reply, so a long conversation uses more of the owner's plan with each turn, gets slower, and in the end gets summarised, which loses detail. A hand-off saved in the brain doesn't. The next chat or agent starts clean, reads one note, and carries on.

It's plain Markdown and git, so any agent can follow it. The nudge is a Claude Code hook (a setting that makes Claude Code run a small script at set moments, like after each tool call): a shortcut, written down below so an agent without it can do the same by hand.

## When to hand off
- **At the end of a stage.** A big job runs in stages ([guide mode](../guide-mode/SKILL.md)), with a hand-off at the end of each. If the next stage carries on in this chat, it can be short; it's there in case the chat ends.
- **At the size nudge,** when the conversation passes 300,000 tokens, and again at each extra 100,000 ([below](#at-the-nudge)). A token is a word or part of a word: about how much the agent reads.
- **When you hand work to an agent:** a brief.
- **When an agent's work is done,** or sooner at its own nudge ([below](#the-sub-agent-nudge)): a report.
- **When a chat has to stop** before the work is done (the owner leaving, their plan's limit coming): the same as the nudge.

No hand-off is needed for a job finished in one go with nothing left for anyone (git has the change), or for a quick search or read whose answer goes straight into your work (its prompt is its brief).

## One format, three ways
| Kind | From and to | What it carries |
|---|---|---|
| `session` | This chat to a fresh one | All the parts below, with the last messages word for word |
| `brief` | A coordinator to an agent | The parts the agent needs, cut down; the gates that bear on the job; what to send back |
| `report` | An agent back to its coordinator | What's done and where, what's open, what it decided on its own, what it learned |

## What goes in one
1. **The ask, in the owner's own words.** Quote the owner (or whoever set the work), with the date, and any later change in their words. A brief gives the coordinator's ask, with the owner's words where they set it.
2. **Where it stands:** what's done, what's half done and in what state, and the next step, clear enough to start on.
3. **Where everything is:** the repo and branch, and whether it's pushed; the files and notes, with links for notes in the brain and paths for files elsewhere; commits and pull requests; and anything outside the repo, like a folder on the owner's PC (`C:\AI-Brain-Link\...`), a live site or preview (its address and host), a job on the PC runner, or an agent still running.
4. **Decisions made, and who made them:** the owner (in their words, linking the decision note you saved) or the agent's own call, marked as that.
5. **Open questions, and what waits on whom:** questions for the owner (each also a task they hold), and anything waiting on someone else, a timer or an agent.
6. **What to read first:** the few notes and files that matter, in order. Not everything.
7. **Watch-outs:** what was tried and didn't work, and why; anything easy to get wrong; what not to redo.
8. **Session hand-offs only: the last few messages, word for word.** The last exchanges with the owner, quoted exactly, so "yes, send it" still makes sense. Go back far enough to cover anything still open. Cut long tool output, never the owner's words.

There's no length limit and no checker (Matt: "We'll just trust the agent to do what they want for the handoff... maybe one needs to be have longer than others"). Decide what each one needs, and skip a part that has nothing in it.

## Save what's lasting first
Before you write the hand-off, put what should outlive it where it belongs, as the [brain spec](../brain-spec/SKILL.md#saving-knowledge) says: the owner's decisions on the decisions shelf, facts in their notes, lessons in a skill's `LESSONS.md` or the friction log, jobs still to do as tasks (the owner's with `holder: owner`), and a dated progress line in the job's task note. The hand-off links to them rather than copying them. So hand-offs stay short, the brain stays the memory, and a later chat finds a fact on its shelf, not buried in an old hand-off. What's left in the hand-off is where the conversation stands.

## Where it goes
One note per hand-off on the [hand-offs shelf](../../knowledge/handoffs/README.md), `knowledge/handoffs/`, named with the date and what it's about: `{KIT_ISO}-shop-website.md`. Its card and shape:
```
---
about: "Session hand-off: <the work>, at <where it stands>. Read to carry it on."
tags: [<project or area>]
kind: session
status: open
before: <file name of the hand-off this one carries on from, if any>
updated: {KIT_DATE}
---
# <The work>: where it stands

**Written** {KIT_DATE}, 09:30 UTC, by <your session link, or who you are>, at <the end of stage 2, the size nudge...>. The job's task: [<task>](../tasks/<task>.md).

## The ask
## Where it stands
## Where everything is
## Decisions
## Open questions
## Read first
## Watch-outs
## The last messages
```
- **`kind`** is `session`, `brief` or `report`. **`before`** names the hand-off this one carries on from (the one your chat started from, or the brief a report answers), so a chain can be followed back. Leave it out if there's none.
- **Statuses:** `open` when written; `picked-up` once someone starts from it; `done` once its work is finished or carried on in a newer hand-off. Whoever does each step changes it.
- **Save it where anyone can get it:** `git pull --rebase`, run `python3 skills/brain-spec/library.py build`, commit only your paths (`git commit -- <paths>`), and push to `main`. A hand-off only on your disk is no hand-off.
- **Whoever picks it up is told its path,** from the repo's root: `knowledge/handoffs/{KIT_ISO}-shop-website.md`.

## At the nudge
In Claude Code, a hook tells you when the conversation passes 300,000 tokens, and again at 400,000 and each extra 100,000. From 500,000 the nudge is urgent, and after that every message the owner sends comes with a reminder to start a fresh chat (Matt, 1 Nov 2026, for brains started from his kit: "every extra 100k definetly. and at 500k, it urges you too. and every message sent after 500k it should tell you to start fresh instance"). Then:
1. **Finish what you're doing.** It's a nudge, not a hard stop. Bring the step you're on to a safe point (a change that works, a message sent, an answer the owner is waiting for), but don't start a new piece. When it's urgent, stop at the first safe point.
2. **Save what's lasting** ([above](#save-whats-lasting-first)).
3. **Write a session hand-off,** with the last messages word for word.
4. **Commit and push** it.
5. **Tell the owner,** in a few plain lines: where things stand, why a fresh chat helps (it goes further on their plan and keeps the detail), and the hand-off's path to paste into a new chat with "continue" or whatever they want to say. Give it ready to paste:
   ```
   knowledge/handoffs/{KIT_ISO}-shop-website.md continue
   ```
6. **Then it's their call:** start the new chat, or carry on here. If you carry on, update the hand-off and push again at the next nudge, and before the chat ends.

The agent never moves the owner to a new chat by itself, and nothing starts up on its own: the owner pastes the path (Matt, 1 Nov 2026: "it will just prompt the person to copy that handoff path, file path, to a new chat, and then say continue or whatever it wants to say"). The pasted path says exactly which hand-off, even with several chats going.

## Starting from a hand-off
When someone gives you a hand-off's path, the owner pasting it or a coordinator in a brief:
1. **Pull** (`git pull --rebase`), so you have it.
2. **Read the core, the hand-off, and what its "Read first" names.** Nothing else up front; open more only when the work needs it.
3. **Mark it picked up:** `status: picked-up`, and a line at its end, `**Picked up** {KIT_DATE}, by <your session link>`. Commit and push, so the board shows it's taken and no second chat starts from it too.
4. **Check what moved since it was written** (`git log --since=<its date> --oneline`), then carry on from its next step. If the owner said more than "continue", their words come first.
5. **When its work is done,** or you hand it on in a new hand-off whose `before` names it, mark it `done`.

## Briefs and reports
The chat the owner talks to is the coordinator, and the agents it hands work to are its helpers, each in a clean thread of its own (Matt: "the coordinator will just be like a normal thread, and then whatever agents it opens underneath that will be its task guys. And then they'll create handoffs to give the coordinator as well"). When to hand work to an agent at all, and how many at once, is in the brain spec ([handing work to an agent](../brain-spec/SKILL.md#handing-work-to-an-agent)).
- **A brief** is a hand-off with `kind: brief`, saved on the shelf and pushed; give the agent its path, with a line on the job in the prompt. Cut it to what the agent needs, add the gates that bear on the job, and say what to send back: a report on the shelf, and its path. The agent can't ask the owner, so put in what it would ask.
- **A report** is a hand-off with `kind: report` and `before` naming the brief. The agent saves it on the shelf, commits only its own paths, pushes, and sends back its path and a few lines as its last message. An agent that can't write files sends the report itself, and the coordinator saves it.
- **The coordinator** reads the report, checks the work once the normal way, saves what's lasting, and marks the brief and the report `done`.
- **The board** is the shelf's own index: the open and picked-up hand-offs, newest first, rebuilt by `library.py build`. A coordinator reads it to see what's in flight, not every hand-off.
- **The coordinator's own hand-off,** at the nudge like any chat, also says what's in flight (agents running, briefs out).

## The sub-agent nudge
An agent you hand work to (a sub-agent) gets one nudge of its own, at 450,000 tokens of its own conversation (Matt, 1 Nov 2026: "We do need a sub-agent nudge. Let's have it trigger at 450, though. Just because it's quite task-based, so it's okay"). Sizing the job first ([guide mode](../guide-mode/SKILL.md)) stays the main way work is split; this is the safety net for when a job turns out bigger than you thought.
- **The agent, at its nudge:** finish the step you're on, write your report back as above (what's done, what's left, and where everything is), and stop. The owner has nothing to paste, and there's no second nudge.
- **The chat that started it** picks up from the report: it checks what's done, and carries on what's left itself or hands it to a fresh agent with the report as its brief.
- **It's separate from the chat's own nudge:** an agent's nudge doesn't use up the chat's, and the chat's never reaches an agent.

## By hand, where no hook runs
The nudge only runs in Claude Code, in a chat started on a copy of this repo. Anywhere else (another AI tool, an agent with no hooks), notice it yourself and hand off the same way (the core's "not tied to one AI provider"). Signs a conversation is long: the tool shows how full its memory is, warns, or starts summarising earlier turns; many long tool outputs, logs or file reads; hours of back-and-forth. In Claude Code you can measure it: `python3 skills/handoff/nudge.py --size <the session's .jsonl log>` (the logs are in `~/.claude/projects/`) prints the size in tokens, and a sub-agent's log, in the session's `subagents/` folder, works the same way. At about 300,000 (450,000 if you're an agent the chat handed work to), or the first time the tool warns or summarises, hand off.

## The nudge's settings
Hooks in `.claude/settings.json` run [nudge.py](nudge.py) after each tool call (`PostToolUse`), when the agent finishes an answer (`Stop`) and when the owner sends a message (`UserPromptSubmit`). It reads the hook's input, takes the conversation's size from the newest main-thread assistant message in the session's log (its input, cache-write and cache-read tokens added up), and when that passes a mark it hasn't nudged for, hands the agent the message: as added context after a tool call or with the owner's message, or by keeping a finished answer going. It remembers which marks a session has had in a small file in the temp folder, named by the session's id. Inside a sub-agent, whose hook input carries `agent_id`, it measures that agent's own conversation instead, after each of its tool calls: from `agent_transcript_path` if the input gives it, or else from the log Claude Code keeps beside the session's, `<the session's log without .jsonl>/subagents/agent-<agent_id>.jsonl`, where every line is marked `isSidechain`. It remembers a sub-agent's one nudge in a file of its own, named by the session's and the agent's ids. It stays silent on a `Stop` already continuing because of a stop hook (`stop_hook_active`), and on any error it prints nothing and exits 0, so it can't break a chat. The hooks run through bash (on Windows, Git Bash, which comes with Git), trying `python3`, then `python`, as the session-start hook does, and doing nothing if neither is there: a claude.ai/code chat has Python, and a Claude Code chat on the owner's PC needs it installed.

The policy is in [nudge.json](nudge.json), not the code; Matt's brain runs the same script with its own:

| Setting | What it does | This brain's |
|---|---|---|
| `first_at` | Tokens at the first nudge; 0 turns the nudge off | 300000 |
| `repeat_every` | Tokens between later nudges; 0 means one only | 100000 |
| `urgent_at` | From this size on, nudges use `urgent_message`; 0 means never | 500000 |
| `every_prompt_after` | From this size on, every message the owner sends gets `prompt_message` (the `UserPromptSubmit` hook); 0 means never | 500000 |
| `agent_at` | Tokens in a sub-agent's own conversation at its one nudge, `agent_message`; 0 means never | 450000 |
| `tell_person` | `true` also shows the message to the owner in Claude Code; off, since it's written for the agent, who tells the owner in plain words | false |
| `state_dir` | Where it remembers the marks; empty means the temp folder | empty |
| `message`, `urgent_message`, `prompt_message`, `agent_message` | What it says; `{size}` and `{mark}` are filled in | |

The owner can change any of these: save it as a decision ([brain spec](../brain-spec/SKILL.md#saving-knowledge)), then change `nudge.json`. To check a change, pipe made-up hook input in, with a made-up session id so no real chat's nudge is used up:
```
echo '{"session_id":"test-1","transcript_path":"<a .jsonl log>","hook_event_name":"PostToolUse"}' | python3 skills/handoff/nudge.py
```
For a sub-agent's nudge, add `"agent_id":"test-agent"` and `"agent_transcript_path":"<its .jsonl log>"`. `--settings <file>` tries other settings.
