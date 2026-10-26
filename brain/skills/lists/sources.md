# Where the copied skills came from

One heading per source: its commit, when Matt's brain copied it, its licence, and the skills this brain has from it. `python3 skills/brain-spec/skill_updates.py` reads the "From" lines to check for updates ([find-skills](../find-skills/SKILL.md)). Each source's README and licence are kept in `skills/sources/` or, for Anthropic's plugins, `skills/anthropic-plugins/`.

This is the record of which skills are copied: a skill with a line here is kept as it came and updated from its source, and any other is the brain's own (a link in these paragraphs doesn't count). `check_links.py` and `library.py` read it to tell them apart. When to use each is in the topic lists. Shared files the copied skills use, kept as they came:

- [anthropic-plugins/](../anthropic-plugins/): Anthropic's plugins' notes and licences.
- [sources/](../sources/): each other source's README and licence.

## addyosmani/agent-skills
From [addyosmani/agent-skills](https://github.com/addyosmani/agent-skills), commit `aeac41d`, copied 19 Oct 2026. Licence: MIT.

- [addyosmani-code-review-and-quality](../addyosmani-code-review-and-quality/SKILL.md)
- [addyosmani-context-engineering](../addyosmani-context-engineering/SKILL.md)
- [addyosmani-idea-refine](../addyosmani-idea-refine/SKILL.md)
- [addyosmani-incremental-implementation](../addyosmani-incremental-implementation/SKILL.md)
- [addyosmani-security-and-hardening](../addyosmani-security-and-hardening/SKILL.md)
- [addyosmani-shipping-and-launch](../addyosmani-shipping-and-launch/SKILL.md)
- [addyosmani-source-driven-development](../addyosmani-source-driven-development/SKILL.md)

## anthropics/claude-plugins-official
From [anthropics/claude-plugins-official](https://github.com/anthropics/claude-plugins-official), commit `ea10b21`, copied 19 Oct 2026. Licence: Apache 2.0.

- [claude-md-management-claude-md-improver](../claude-md-management-claude-md-improver/SKILL.md)

## anthropics/knowledge-work-plugins
From [anthropics/knowledge-work-plugins](https://github.com/anthropics/knowledge-work-plugins), commit `33d3dea`, copied 19 Oct 2026. Licence: Apache 2.0.

- [data-analyze](../data-analyze/SKILL.md)
- [product-management-write-spec](../product-management-write-spec/SKILL.md)
- [small-business-cash-flow-snapshot](../small-business-cash-flow-snapshot/SKILL.md)
- [small-business-invoice-chase](../small-business-invoice-chase/SKILL.md)
- [small-business-proposal-builder](../small-business-proposal-builder/SKILL.md)

## anthropics/skills
From [anthropics/skills](https://github.com/anthropics/skills), commit `dbd4588`, copied 19 Oct 2026. Licence: Apache 2.0.

- [academy-guide](../academy-guide/SKILL.md)
- [claude-api](../claude-api/SKILL.md)
- [webapp-testing](../webapp-testing/SKILL.md)

## coreyhaines31/marketingskills
From [coreyhaines31/marketingskills](https://github.com/coreyhaines31/marketingskills), commit `e85f3cb`, copied 19 Oct 2026. Licence: MIT.

- [marketingskills-copywriting](../marketingskills-copywriting/SKILL.md)
- [marketingskills-customer-research](../marketingskills-customer-research/SKILL.md)
- [marketingskills-launch](../marketingskills-launch/SKILL.md)
- [marketingskills-marketing-ideas](../marketingskills-marketing-ideas/SKILL.md)
- [marketingskills-pricing](../marketingskills-pricing/SKILL.md)

## Leonxlnx/taste-skill
From [Leonxlnx/taste-skill](https://github.com/Leonxlnx/taste-skill), commit `6010f91`, copied 19 Oct 2026. Licence: MIT.

- [taste-skill](../taste-skill/SKILL.md)

## mattpocock/skills
From [mattpocock/skills](https://github.com/mattpocock/skills), commit `5beb35b`, copied 19 Oct 2026. Licence: MIT.

- [mattpocock-grilling](../mattpocock-grilling/SKILL.md)
- [mattpocock-prototype](../mattpocock-prototype/SKILL.md)
- [mattpocock-teach](../mattpocock-teach/SKILL.md)
- [mattpocock-wizard](../mattpocock-wizard/SKILL.md)
- [mattpocock-writing-for-agents](../mattpocock-writing-for-agents/SKILL.md)

## obra/superpowers
From [obra/superpowers](https://github.com/obra/superpowers), commit `2ce8aa1`, copied 19 Oct 2026. Licence: MIT.

- [superpowers-brainstorming](../superpowers-brainstorming/SKILL.md)
- [superpowers-systematic-debugging](../superpowers-systematic-debugging/SKILL.md)
- [superpowers-test-driven-development](../superpowers-test-driven-development/SKILL.md)
- [superpowers-verification-before-completion](../superpowers-verification-before-completion/SKILL.md)
- [superpowers-writing-plans](../superpowers-writing-plans/SKILL.md)

## pbakaus/impeccable
From [pbakaus/impeccable](https://github.com/pbakaus/impeccable), commit `9368675`, copied 19 Oct 2026. Licence: Apache 2.0.

- [impeccable](../impeccable/SKILL.md)

## vercel-labs/agent-skills
From [vercel-labs/agent-skills](https://github.com/vercel-labs/agent-skills), commit `063bee9`, copied 19 Oct 2026. Licence: MIT.

- [vercel-deploy-to-vercel](../vercel-deploy-to-vercel/SKILL.md)
- [vercel-web-design-guidelines](../vercel-web-design-guidelines/SKILL.md)

## kepano/obsidian-skills
From [kepano/obsidian-skills](https://github.com/kepano/obsidian-skills), commit `3ccff53`, copied 19 Oct 2026. Licence: MIT.

- [obsidian-bases](../obsidian-bases/SKILL.md)
- [obsidian-defuddle](../obsidian-defuddle/SKILL.md)
- [obsidian-json-canvas](../obsidian-json-canvas/SKILL.md)
- [obsidian-markdown](../obsidian-markdown/SKILL.md)

## Anthropic, copied 18 Oct 2026
Copied into Matt's brain from a Claude session's own copies of Anthropic's skills and plugins, with no commit. `skill_updates.py check` compares them with the copies in a Claude session (`/mnt/skills/`, `~/.claude/`). Licence: Apache 2.0 (a `LICENSE.txt` in each skill, or its plugin's in `skills/anthropic-plugins/`).

- [canvas-design](../canvas-design/SKILL.md)
- [design-design-critique](../design-design-critique/SKILL.md)
- [design-ux-copy](../design-ux-copy/SKILL.md)
- [engineering-system-design](../engineering-system-design/SKILL.md)
- [event-planning](../event-planning/SKILL.md)
- [financial-calculator](../financial-calculator/SKILL.md)
- [frontend-design](../frontend-design/SKILL.md)
- [learn](../learn/SKILL.md)
- [marketing-competitive-brief](../marketing-competitive-brief/SKILL.md)
- [marketing-content-creation](../marketing-content-creation/SKILL.md)
- [marketing-email-sequence](../marketing-email-sequence/SKILL.md)
- [marketing-seo-audit](../marketing-seo-audit/SKILL.md)
- [mcp-builder](../mcp-builder/SKILL.md)
- [skill-creator](../skill-creator/SKILL.md)
- [theme-factory](../theme-factory/SKILL.md)
