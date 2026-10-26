---
about: "The knowledge library, the brain's memory of what's true: one line per shelf. Start here to find anything about the owner, their projects, their systems or what they decided."
updated: {KIT_DATE}
---
# The knowledge library

What the brain knows, as plain Markdown notes. How to do things is the other library, the [skills](../skills/README.md). The shelves start almost empty and fill up as the owner and their agents work.

- **A note's folder says what kind of thing it is; its tags say what it's about.** A tag is the name of a project, area or subject. So everything about one project is one question: `python3 skills/brain-spec/library.py find --tag <project>`.
- **Every note starts with a card**: an `about` line saying what's in it and when you'd read it, its tags, its status and when it was last checked. Pick notes by their cards, and open only the ones your job needs.
- **Each shelf's `README.md` is its index.** The lists between the index marks are built from the cards by `python3 skills/brain-spec/library.py build` (a GitHub Action runs it on every push), so don't edit them by hand.
- **It's there to be added to.** What to save, where, and how: the [brain-spec skill](../skills/brain-spec/SKILL.md).

<!-- index:start -->
- [areas/](areas/README.md): Ongoing things with no end: the brain itself, later others such as money, health or home. Read for the overall picture of an area.
- [decisions/](decisions/README.md): What the owner decided, standing rules included, one note per decision on a sub-shelf per project or area. Read before changing anything a rule might cover.
- [ideas/](ideas/README.md): Ideas not started yet, the friction log included, one note each. Read before proposing something new, in case it's here already.
- [people/](people/README.md): The owner, customers, suppliers and contacts, one note per person. Read before working with or writing to someone.
- [subjects/](subjects/README.md): The open library, one note or folder per field of knowledge, kept when facts took effort to get. Read when a job needs facts about a field rather than about the owner's own work.
- [systems/](systems/README.md): The machinery the brain runs on: the owner's PC and its runner, accounts and keys, routines, Obsidian and the brain graph. Read before using an account, the PC or a routine.
- [tasks/](tasks/README.md): What's in flight: open tasks, who holds them, and what waits on the owner. Read to see what needs doing now, or before you hand work on.
- [ventures/](ventures/README.md): Things with a goal: the owner's projects, businesses and client work, one note or folder each. Read before any work on a project, for what it is, its goal, its code and its look.
<!-- index:end -->
