---
name: find-skills
description: "How to find and add a good skill from outside the brain: what's already here, which sources to trust first (Anthropic, then the company behind a tool, then very popular collections), the quality bar, copying a skill in unchanged, its licence, listing it, and keeping copied skills up to date. Use when the owner asks for a skill, or when a job would go better with one the brain doesn't have."
---

# Finding skills
The brain starts with 63 skills. Everything else comes in when a job needs it, the way Matt's brain does it (Matt, 19 Oct 2026: "they have to be high quality skills, obviously use ones from Anthropic first. And then potentially like very popular or or highly um, rated GitHub ones").

## First, check what's here
- The [skills list](../README.md).
- **Claude's own skills.** A Claude session already has Anthropic's skills for Word, PDF, Excel and PowerPoint files, deep research and a few more, so don't copy those in. Another agent can copy them from [anthropics/skills](https://github.com/anthropics/skills) when it needs them; some are licensed for your own use only.

## Where to look, in order
1. **Anthropic's:** [anthropics/skills](https://github.com/anthropics/skills), [anthropics/knowledge-work-plugins](https://github.com/anthropics/knowledge-work-plugins) (business, marketing, sales, finance, design, engineering, data), [anthropics/financial-services-plugins](https://github.com/anthropics/financial-services-plugins) and [anthropics/claude-plugins-official](https://github.com/anthropics/claude-plugins-official). In a Claude session they're also in `/mnt/skills/` and `~/.claude/`.
2. **The company behind the tool,** when a job uses one: for example [cloudflare/skills](https://github.com/cloudflare/skills), [stripe/ai](https://github.com/stripe/ai), [vercel-labs/agent-skills](https://github.com/vercel-labs/agent-skills), [supabase/agent-skills](https://github.com/supabase/agent-skills), [expo/skills](https://github.com/expo/skills), [firebase/agent-skills](https://github.com/firebase/agent-skills), [huggingface/skills](https://github.com/huggingface/skills), [openai/skills](https://github.com/openai/skills), [elevenlabs/skills](https://github.com/elevenlabs/skills), [remotion-dev/skills](https://github.com/remotion-dev/skills) and [heygen-com/hyperframes](https://github.com/heygen-com/hyperframes) (video made with code).
3. **Community collections with a big following.** The bar in Matt's brain is tens of thousands of GitHub stars, or an official company repo. Stars as counted there on 19 Oct 2026: [obra/superpowers](https://github.com/obra/superpowers) about 302k (planning, debugging, testing), [mattpocock/skills](https://github.com/mattpocock/skills) about 296k, [addyosmani/agent-skills](https://github.com/addyosmani/agent-skills) about 108k, [coreyhaines31/marketingskills](https://github.com/coreyhaines31/marketingskills) about 55k, [kepano/obsidian-skills](https://github.com/kepano/obsidian-skills) about 50k; also [pbakaus/impeccable](https://github.com/pbakaus/impeccable), [Leonxlnx/taste-skill](https://github.com/Leonxlnx/taste-skill) and [emilkowalski/skills](https://github.com/emilkowalski/skills) for better-looking sites, and [trailofbits/skills](https://github.com/trailofbits/skills) for security. Rankings to check: [skills.sh](https://skills.sh) and `LinklyAI/best-skills` on GitHub.

If nothing passes the bar, write a skill from the tool's official docs, with [skill-creator](../skill-creator/SKILL.md).

## Copying one in
1. **Get the source at a fixed commit:** clone it shallowly into a temporary folder outside the brain, and note the commit (`git rev-parse --short HEAD`).
2. **Copy the skill's folder into `skills/` unchanged.** Its folder name: an Anthropic plugin's skill is `<plugin>-<skill>`; another source's is `<source>-<skill>` (`superpowers-brainstorming`), unless its name already names the maker's product (`stripe-`, `vercel-`). Change only its `name:` line to match the folder, and links to shared files outside its folder: copy those into `skills/anthropic-plugins/<plugin>/` or `skills/sources/<owner>-<repo>/` and point the links there.
3. **Keep the source's README and licence** in `skills/sources/<owner>-<repo>/`.
4. **Check the licence,** and tell the owner in a line: MIT, Apache 2.0 and BSD are fine for anything; CC BY-SA means credit the makers and share changes the same way; no licence at all means all rights reserved (fine to use in the brain, not to sell or hand on); GPL or AGPL needs the owner's say before it goes into anything sold (the core's "reuse before you build").
5. **Read it once** for anything unsafe, and for anything that fights the core, such as extra reviewers on every change. The core wins; say so in its line in the list.
6. **List it twice:** a line in the right topic list in `skills/lists/`, under its copied skills (the [skills list](../README.md) links every list under "The lists by topic"), saying when to use it; and a line under its source in [lists/sources.md](../lists/sources.md), the record of which skills are copied, like this (a new source gets a heading; the commit goes only here):
   ```
   ## owner/repo
   From [owner/repo](https://github.com/owner/repo), commit `abc1234`, copied 22 Oct 2026. Licence: MIT.

   - [name](../name/SKILL.md): what it's for
   ```
   Then run `python3 skills/brain-spec/skill_updates.py map`.
7. **Commit** ("Copied <skills> from <owner/repo>") and push.

No topic fits: start a new list in `skills/lists/`, with a heading and a line saying what's in it, and link it from the skills list under "The lists by topic". A list holds the brain's own skills and copied ones together, the brain's own first under "The brain's own"; the scripts tell them apart by `sources.md`, so a copied skill missing from it would be taken for the brain's own and held to its rules. A copied skill never goes on the skills list itself, which every agent reads and so stays short (`library.py check` flags it past 6 KB).

## Keeping them up to date
`python3 skills/brain-spec/skill_updates.py check` lists copied skills that changed, moved or were deleted at their source since they were copied. `update --source owner/repo` (try `--dry-run` first) brings a set up to date and keeps the brain's own changes. Read the diff before committing. It needs git and github.com.

## Lessons on a copied skill
A copied skill's text stays as it came. When one lets you down, the lesson goes in a `LESSONS.md` in its folder, linked from an `## In this brain` section at the end of its `SKILL.md` ([how skills learn](../brain-spec/SKILL.md#how-skills-learn)).
