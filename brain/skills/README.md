# Skills

Every skill in the brain, one line each, so any agent can find the one its job needs without opening them all. Any agent, Claude Code included, reads this list and opens the `SKILL.md` it needs. How a skill is shaped and when to write one: the [brain spec](brain-spec/SKILL.md#a-skill). To find and add more: [find-skills](find-skills/SKILL.md).

## The brain's own
Written for this brain. Change them freely, and add a line here for a new one. Any skill can have a `LESSONS.md` beside it: what agents learned using it here ([how skills learn](brain-spec/SKILL.md#how-skills-learn)).
- [getting-started](getting-started/SKILL.md): the first session in a new brain: who the owner is, their first notes, testing the PC runner, and a tour.
- [guide-mode](guide-mode/SKILL.md): how to work with an owner new to AI agents: say the ask back, size it, agree a plan, check in.
- [brain-spec](brain-spec/SKILL.md): where each kind of thing goes in the brain and what shape it takes.
- [brain-audit](brain-audit/SKILL.md): the weekly tidy-up, when the owner says yes to it.
- [find-skills](find-skills/SKILL.md): find a good skill from outside the brain, copy it in, and keep copied skills up to date.
- [my-pc](my-pc/SKILL.md): run commands and jobs on the owner's PC through the `my-pc` runner, and check or fix its setup.

## Copied skills
Kept as they came, from Anthropic first, then the companies behind the tools, then very popular collections. All are under the MIT or Apache 2.0 licence. Their sources, commits and licences are in [lists/sources.md](lists/sources.md). What was changed, and nothing else: each folder's name (an Anthropic plugin's skill is `<plugin>-<skill>`, another source's `<source>-<skill>`), its `name:` line to match, and links to shared files, which are in [anthropic-plugins/](anthropic-plugins/) (Anthropic's plugins' notes and licences) and [sources/](sources/) (each other source's README and licence). Where a copied skill names a sibling as `superpowers:<name>`, the brain's copy is `superpowers-<name>`, and the same for the other sets. In Matt Pocock's skills, "Matt" means Matt Pocock. Where one asks for more reviewers or checks than the core's "one check is enough", the core wins.

A Claude session also has Anthropic's own skills for Word, PDF, Excel and PowerPoint files, deep research and a few more, without copies here.

### Claude-only parts, and the plain way
Some of these skills were written for Claude's apps. Any agent can do the same with these swaps.

| When a skill says | Do this instead |
|---|---|
| Render or publish an artifact | Write the HTML file and open it in a browser, or send it to the owner |
| Connectors, or "suggest a connector" | Use whatever tool you have for that app, and tell the owner in words which app to connect |
| Ask with choice cards | Ask in plain text, with numbered options |
| Spawn subagents | Do the steps yourself, one after another |
| Set up a scheduled task | A row in [routines](../knowledge/systems/routines.md); a scheduled AI job needs the owner's yes |
| Claude's memory, a `CLAUDE.md` memory or `TASKS.md` | The brain's own notes: the [knowledge library](../knowledge/README.md), with tasks on its tasks shelf |
| Claude in Chrome, the built-in browser, computer use | Your own browser or desktop tool, or a job on the owner's PC ([my-pc](my-pc/SKILL.md)) |

### Planning, thinking and learning
- [superpowers-brainstorming](superpowers-brainstorming/SKILL.md): shape a new project or feature before building it, one question at a time.
- [addyosmani-idea-refine](addyosmani-idea-refine/SKILL.md): turn a rough business or product idea into something worth trying.
- [mattpocock-grilling](mattpocock-grilling/SKILL.md): get grilled on a plan until its gaps show.
- [superpowers-writing-plans](superpowers-writing-plans/SKILL.md): write a step-by-step plan for a change with several steps.
- [product-management-write-spec](product-management-write-spec/SKILL.md): write a spec for a product or feature.
- [mattpocock-wizard](mattpocock-wizard/SKILL.md): walk the owner through steps only they can do, one at a time.
- [mattpocock-teach](mattpocock-teach/SKILL.md): teach a topic over several sessions. [learn](learn/SKILL.md): teach a concept so it sticks, rather than just answer.
- [academy-guide](academy-guide/SKILL.md): point someone learning Claude to a matching free Anthropic Academy course.

### Building and fixing code
- [addyosmani-incremental-implementation](addyosmani-incremental-implementation/SKILL.md): build a change or carry out a plan, one small working step at a time.
- [mattpocock-prototype](mattpocock-prototype/SKILL.md): answer a design question with quick throwaway code.
- [superpowers-test-driven-development](superpowers-test-driven-development/SKILL.md): write the test first, then the code.
- [superpowers-systematic-debugging](superpowers-systematic-debugging/SKILL.md): find the real cause of a bug before fixing it.
- [superpowers-verification-before-completion](superpowers-verification-before-completion/SKILL.md): check it really works before saying it's done.
- [addyosmani-code-review-and-quality](addyosmani-code-review-and-quality/SKILL.md): review code or a diff.
- [addyosmani-source-driven-development](addyosmani-source-driven-development/SKILL.md): use a framework or API the way its current docs say.
- [addyosmani-security-and-hardening](addyosmani-security-and-hardening/SKILL.md): build securely, and handle untrusted input.
- [addyosmani-shipping-and-launch](addyosmani-shipping-and-launch/SKILL.md): launch or deploy a site or feature.
- [addyosmani-context-engineering](addyosmani-context-engineering/SKILL.md): keep an agent's context lean, and leave work ready for the next session.
- [engineering-system-design](engineering-system-design/SKILL.md): design a new system or service.

### Websites and design
- [frontend-design](frontend-design/SKILL.md): distinctive web design that doesn't look templated.
- [impeccable](impeccable/SKILL.md), [taste-skill](taste-skill/SKILL.md): better-looking interfaces, with taste.
- [vercel-web-design-guidelines](vercel-web-design-guidelines/SKILL.md): check a page against web interface guidelines.
- [vercel-deploy-to-vercel](vercel-deploy-to-vercel/SKILL.md): put a site live on Vercel.
- [webapp-testing](webapp-testing/SKILL.md): test a web app in a real browser with Playwright.
- [design-design-critique](design-design-critique/SKILL.md): a structured critique of a design. [design-ux-copy](design-ux-copy/SKILL.md): the words on buttons, forms and errors.
- [theme-factory](theme-factory/SKILL.md): ready-made colour and font themes. [canvas-design](canvas-design/SKILL.md): posters and static art.

### AI, Claude and skills
- [claude-api](claude-api/SKILL.md): build on the Claude API: models, prices, tools, caching.
- [mcp-builder](mcp-builder/SKILL.md): build an MCP server, so agents can use a tool.
- [skill-creator](skill-creator/SKILL.md): make, test and tune a skill.
- [mattpocock-writing-for-agents](mattpocock-writing-for-agents/SKILL.md): write notes and instructions agents follow well.
- [claude-md-management-claude-md-improver](claude-md-management-claude-md-improver/SKILL.md): improve a project's `CLAUDE.md`.

### Obsidian
From [kepano/obsidian-skills](https://github.com/kepano/obsidian-skills), by Obsidian's CEO.
- [obsidian-markdown](obsidian-markdown/SKILL.md): Obsidian's Markdown: callouts, embeds, properties.
- [obsidian-bases](obsidian-bases/SKILL.md): database-like views of notes. [obsidian-json-canvas](obsidian-json-canvas/SKILL.md): canvases of cards and links.
- [obsidian-defuddle](obsidian-defuddle/SKILL.md): clean a web page into Markdown.

### Business, marketing and money
- [marketingskills-marketing-ideas](marketingskills-marketing-ideas/SKILL.md): marketing ideas that fit a product. [marketingskills-customer-research](marketingskills-customer-research/SKILL.md): learn what customers want.
- [marketingskills-copywriting](marketingskills-copywriting/SKILL.md): words that sell, for pages and ads. [marketingskills-pricing](marketingskills-pricing/SKILL.md): set and test prices. [marketingskills-launch](marketingskills-launch/SKILL.md): plan a launch.
- [marketing-content-creation](marketing-content-creation/SKILL.md): posts, articles and other content. [marketing-email-sequence](marketing-email-sequence/SKILL.md): a series of emails.
- [marketing-seo-audit](marketing-seo-audit/SKILL.md): how a site shows up in search. [marketing-competitive-brief](marketing-competitive-brief/SKILL.md): what competitors do.
- [small-business-proposal-builder](small-business-proposal-builder/SKILL.md): a proposal or quote for a client. [small-business-invoice-chase](small-business-invoice-chase/SKILL.md): chase unpaid invoices. [small-business-cash-flow-snapshot](small-business-cash-flow-snapshot/SKILL.md): where the money stands.
- [data-analyze](data-analyze/SKILL.md): answer a question from data.
- [financial-calculator](financial-calculator/SKILL.md): tax, loan, investment and rent-or-buy sums.

### Life admin
- [event-planning](event-planning/SKILL.md): plan an event, from guest list to the day.
