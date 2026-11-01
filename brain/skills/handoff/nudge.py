#!/usr/bin/env python3
"""The hand-off nudge: tells the agent when a conversation has grown long enough to hand off.

Claude Code runs it from hooks in .claude/settings.json, after each tool call (PostToolUse)
and when the agent finishes an answer (Stop); a UserPromptSubmit hook can run it too. It
reads the hook's JSON on stdin, works out how big the conversation is from the newest
main-thread assistant message in the session's log (the transcript), and when the size
passes a mark it hasn't nudged for yet, it prints the nudge for Claude Code to hand the
agent. What the agent then does is in the handoff skill (skills/handoff/SKILL.md).

A sub-agent gets one nudge of its own (Matt, 1 Nov 2026: "We do need a sub-agent nudge.
Let's have it trigger at 450"). Inside one, the hook input carries `agent_id`, and after each
of its tool calls the script measures that sub-agent's own conversation, from its own log:
`agent_transcript_path` if the input gives it, or else the log Claude Code keeps beside the
main transcript, <dir>/<session>/subagents/agent-<agent_id>.jsonl for <dir>/<session>.jsonl,
where every line is marked `isSidechain`. At agent_at it tells the sub-agent, once, to finish
its step, report back and stop. It remembers that in a state file of the sub-agent's own, so
it never uses up the main chat's nudge, and the main chat's nudges never go to a sub-agent.

The policy lives in nudge.json beside this script, not in the code, so another brain (the
friends' kit) can use the same script with its own marks. Matt's brain (1 Nov 2026): one
nudge per session, at 300,000 tokens, and one per sub-agent, at 450,000. The settings:
  first_at            tokens at the first nudge; 0 turns the nudge off
  repeat_every        tokens between later nudges; 0 means one nudge only
  urgent_at           from this size on, nudges use urgent_message; 0 means never
  every_prompt_after  from this size on, every message the person sends gets prompt_message
                      (needs a UserPromptSubmit hook); 0 means never
  agent_at            tokens in a sub-agent's own conversation at its one nudge,
                      agent_message; 0 means never
  tell_person         true also shows the message to the person in Claude Code
  state_dir           where it remembers which nudges a session has had; "" means the
                      system's temp folder
  message, urgent_message, prompt_message, agent_message
                      what it says; {size} and {mark} are filled in, like "312,000"
Anything left out of nudge.json takes the default below.

It never breaks a session: on any error, a missing transcript or bad settings it prints
nothing and exits 0. It stays silent on a Stop that is already continuing because of a stop
hook (`stop_hook_active`), so it can't loop, and in a sub-agent on anything but PostToolUse.

By hand: `python3 skills/handoff/nudge.py --size TRANSCRIPT.jsonl` prints a conversation's
size, a sub-agent's log included. Tests pipe made-up hook input in, with `--settings FILE`
for other settings. Python 3.8 or later, standard library only.
"""
import json
import os
import re
import sys
import tempfile
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
SETTINGS = os.path.join(HERE, "nudge.json")
DEFAULTS = {
    "first_at": 300000,
    "repeat_every": 0,
    "urgent_at": 0,
    "every_prompt_after": 0,
    "agent_at": 450000,
    "tell_person": False,
    "state_dir": "",
    "message": ("Hand-off nudge: this conversation is about {size} tokens, past the {mark} mark. It's a nudge, "
                "not a hard stop: finish what you're doing first. Then follow the handoff skill "
                "(skills/handoff/SKILL.md): save what's lasting to the library, write a session hand-off on "
                "the hand-offs shelf (knowledge/handoffs/), commit and push, and tell the person its path to "
                "paste into a new chat with \"continue\"."),
    "urgent_message": ("Hand-off nudge, urgent: this conversation is about {size} tokens, past {mark}. Long "
                       "conversations get slower, cost more and lose detail. Finish the step you're on, then "
                       "hand off now, the way the handoff skill (skills/handoff/SKILL.md) says, and tell the "
                       "person the hand-off's path to paste into a new chat."),
    "prompt_message": ("This conversation is about {size} tokens, past {mark}. Before anything else, tell the "
                       "person it's time to start a fresh chat. If there's no hand-off yet, write one the way "
                       "the handoff skill (skills/handoff/SKILL.md) says, and give them its path to paste."),
    "agent_message": ("Sub-agent hand-off nudge: your own conversation is about {size} tokens, past the {mark} mark "
                      "for agents. Finish the step you're on, then write your report back the way the handoff skill "
                      "(skills/handoff/SKILL.md, \"Briefs and reports\") says: what's done, what's left, and where "
                      "everything is. Then stop: the session that started you picks up from your report. This is "
                      "your only nudge."),
}
CHUNK = 64 * 1024        # bytes read at a time, from the end of the transcript
MOST = 64 * 1024 * 1024  # bytes it reads back at most, so a huge log can't stall a hook


def settings(path=SETTINGS):
    out = dict(DEFAULTS)
    try:
        with open(path, encoding="utf-8") as fh:
            got = json.load(fh)
        out.update({k: v for k, v in got.items() if k in DEFAULTS})
    except (OSError, ValueError, AttributeError):
        pass
    return out


def tokens(value):
    try:
        return max(int(value or 0), 0)
    except (TypeError, ValueError):
        return 0


def size_of(line, side=False):
    """The conversation's size from one transcript line, if it's an assistant message with usage: a main-thread one,
    or with side true any, since every line in a sub-agent's own log is a sidechain one."""
    if b'"assistant"' not in line or b'"usage"' not in line:
        return None
    try:
        entry = json.loads(line)
    except ValueError:
        return None
    if not isinstance(entry, dict) or entry.get("type") != "assistant" or (entry.get("isSidechain") and not side):
        return None
    usage = (entry.get("message") or {}).get("usage") or {}
    total = sum(tokens(usage.get(k)) for k in ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"))
    return total or None  # a stand-in message (an error, say) has no usage: keep looking


def conversation_size(path, side=False):
    """Tokens in the conversation as of its newest assistant message (main-thread, unless side), read from the end of the log."""
    with open(path, "rb") as fh:
        fh.seek(0, os.SEEK_END)
        pos = fh.tell()
        rest, read = b"", 0
        while pos > 0 and read < MOST:
            step = min(CHUNK, pos)
            pos -= step
            read += step
            fh.seek(pos)
            lines = (fh.read(step) + rest).split(b"\n")
            rest = lines.pop(0)  # may be the end of a line that starts further back
            for line in reversed(lines):
                n = size_of(line, side)
                if n:
                    return n
        return size_of(rest, side) if pos == 0 else None


def state_file(conf, name):
    folder = conf.get("state_dir") or os.path.join(tempfile.gettempdir(), "handoff-nudge")
    name = re.sub(r"[^A-Za-z0-9_.-]", "_", name)[:200]
    return os.path.join(folder, name + ".json")


def load_state(path):
    try:
        with open(path, encoding="utf-8") as fh:
            got = json.load(fh)
        return got if isinstance(got, dict) else {}
    except (OSError, ValueError):
        return {}


def save_state(path, state):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(state, fh)
    os.replace(tmp, path)


def stamp():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def mark_for(size, conf):
    """The highest mark the size has passed, or 0."""
    first, every = tokens(conf["first_at"]), tokens(conf["repeat_every"])
    if not first or size < first:
        return 0
    return first + ((size - first) // every) * every if every else first


def fill(template, size, mark):
    return str(template).replace("{size}", f"{size:,}").replace("{mark}", f"{mark:,}")


def agent_log(hook, agent):
    """A sub-agent's own log: the agent_transcript_path the hook gives, or the one Claude Code keeps beside the main
    transcript (<dir>/<session>.jsonl -> <dir>/<session>/subagents/agent-<agent_id>.jsonl). None if it isn't there."""
    paths = [os.path.expanduser(str(hook["agent_transcript_path"]))] if hook.get("agent_transcript_path") else []
    main = os.path.expanduser(str(hook.get("transcript_path") or ""))
    if main.endswith(".jsonl") and re.match(r"^[A-Za-z0-9_-]+$", agent):
        names = ["agent-" + agent + ".jsonl"] + ([agent + ".jsonl"] if agent.startswith("agent-") else [])
        if os.path.basename(main) in names:
            paths.append(main)  # the hook gave the sub-agent's own log already
        paths += [os.path.join(main[:-len(".jsonl")], "subagents", name) for name in names]
    return next((p for p in paths if os.path.isfile(p)), None)


def agent_nudge(hook, conf, session, agent):
    """A sub-agent's one nudge, at agent_at tokens of its own conversation: what to print, and the state to save."""
    at = tokens(conf["agent_at"])
    if not at:
        return None, None
    path = state_file(conf, f"{session}.agent-{agent}")  # its own file, so the main chat's nudge is never used up
    if tokens(load_state(path).get("last_mark")):
        return None, None  # it has had its nudge: no repeats
    log = agent_log(hook, agent)
    size = conversation_size(log, side=True) if log else None
    if not size or size < at:
        return None, None
    message = fill(conf["agent_message"], size, at)
    out = {"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": message}}
    if conf.get("tell_person") is True:
        out["systemMessage"] = message
    return out, (path, {"agent_id": agent, "last_mark": at, "size": size, "event": "PostToolUse", "at": stamp()})


def decide(hook, conf):
    """What to print for this hook call, as a dict, or None; and the state to save, or None."""
    event = hook.get("hook_event_name")
    session, transcript = hook.get("session_id"), hook.get("transcript_path")
    if event not in ("PostToolUse", "Stop", "UserPromptSubmit") or not session:
        return None, None
    if hook.get("agent_id"):
        # A sub-agent's call: its own nudge, after a tool call; the main chat's nudges never go to it.
        return agent_nudge(hook, conf, str(session), str(hook["agent_id"])) if event == "PostToolUse" else (None, None)
    if not transcript:
        return None, None
    if event == "Stop" and hook.get("stop_hook_active"):
        return None, None  # already continuing because of a stop hook; the next call can nudge
    path = state_file(conf, str(session))
    state = load_state(path)
    last = tokens(state.get("last_mark"))
    first, every, prompt_after = tokens(conf["first_at"]), tokens(conf["repeat_every"]), tokens(conf["every_prompt_after"])
    if (not first or (not every and last >= first)) and not (event == "UserPromptSubmit" and prompt_after):
        return None, None  # nothing left to say this session: skip reading the log
    transcript = os.path.expanduser(str(transcript))
    if not os.path.isfile(transcript):
        return None, None
    size = conversation_size(transcript)
    if not size:
        return None, None
    mark = mark_for(size, conf)
    message, new_state = None, None
    if mark > last:
        urgent = tokens(conf["urgent_at"])
        message = fill(conf["urgent_message"] if urgent and mark >= urgent else conf["message"], size, mark)
        new_state = dict(state, last_mark=mark, size=size, event=event, at=stamp())
        new_state["marks"] = sorted(set(state.get("marks", [])) | {mark})
    elif event == "UserPromptSubmit" and prompt_after and size >= prompt_after:
        message = fill(conf["prompt_message"], size, prompt_after)
    if not message:
        return None, None
    if event == "Stop":
        out = {"decision": "block", "reason": message}
    else:
        out = {"hookSpecificOutput": {"hookEventName": event, "additionalContext": message}}
    if conf.get("tell_person") is True:
        out["systemMessage"] = message
    return out, (path, new_state) if new_state else None


def main(argv):
    conf_path = SETTINGS
    if len(argv) >= 2 and argv[0] == "--size":
        print(conversation_size(argv[1]) or conversation_size(argv[1], side=True) or 0)  # a sub-agent's log is all sidechain
        return
    if len(argv) >= 2 and argv[0] == "--settings":
        conf_path = argv[1]
    hook = json.loads(sys.stdin.read() or "{}")
    if not isinstance(hook, dict):
        return
    out, save = decide(hook, settings(conf_path))
    if out:
        if save:
            save_state(*save)  # remember it first, so a failed save can't nudge on every call
        sys.stdout.write(json.dumps(out) + "\n")


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except BaseException:  # never break a session, whatever went wrong
        pass
    sys.exit(0)
