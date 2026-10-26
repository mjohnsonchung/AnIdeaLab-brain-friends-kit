#!/usr/bin/env python3
"""A small test of library.py: build, find and check a throwaway knowledge/ tree.

Run it from anywhere: python3 skills/brain-spec/test_library.py
It makes the tree in a temporary folder and never touches the brain itself.
"""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import library  # noqa: E402

SHELF = """---
about: "{about}"
updated: 19 Oct 2026
---
# {title}

<!-- index:start -->
<!-- index:end -->
"""


def note(about, **fields):
    lines = ["---", f'about: "{about}"']
    lines += [f"{k}: {v}" for k, v in fields.items()]
    if "updated" not in fields:
        lines.append("updated: 19 Oct 2026")
    return "\n".join(lines + ["---", "# A note", ""])


class LibraryTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = self.tmp.name
        files = {
            "CLAUDE.md": "# The core\n",
            "knowledge/README.md": SHELF.format(about="The library.", title="Knowledge"),
            "knowledge/tasks/README.md": SHELF.format(about="What's in flight.", title="Tasks"),
            "knowledge/tasks/send-pack.md": note("Matt sends the pack.", tags="[law-office]", status="open",
                                                 holder="owner", due="23 Oct 2026"),
            "knowledge/tasks/build-site.md": note("Build the site.", tags="[drivermods]", status="doing",
                                                  holder="https://claude.ai/code/session_x"),
            "knowledge/tasks/old-job.md": note("An old job.", status="done", holder="open"),
            "knowledge/tasks/bad-holder.md": note("Nobody knows.", status="open", holder="bob"),
            "knowledge/ventures/README.md": SHELF.format(about="Things with a goal.", title="Ventures"),
            "knowledge/ventures/drivermods/README.md": SHELF.format(about="The store.", title="DriverMods"),
            "knowledge/ventures/drivermods/order-flow.md": note("How an order flows.", tags="[drivermods, money]"),
            "knowledge/ventures/law-office.md": note("The law venture."),
            "knowledge/ventures/lab/README.md": SHELF.format(about="The lab.", title="Lab"),
            "knowledge/ventures/lab/robot/README.md": SHELF.format(about="A project in the lab.", title="Robot"),
            "knowledge/ventures/lab/history/README.md": SHELF.format(about="Old notes.", title="History"),
            "knowledge/tasks/build-robot.md": note("Build the robot.", tags="[lab, robot]", status="open",
                                                   holder="open"),
            "knowledge/areas/README.md": SHELF.format(about="Ongoing things.", title="Areas"),
            "knowledge/areas/money.md": note("The money picture."),
            "knowledge/decisions/README.md": SHELF.format(about="What Matt decided.", title="Decisions"),
            "knowledge/decisions/2026-10-17-older.md": note("An older one.", status="current"),
            "knowledge/decisions/2026-10-18-newer.md": note("A newer one.", status="current", tags="[nowhere]"),
            "knowledge/decisions/2026-10-01-gone.md": note("Replaced.", status="superseded"),
            "knowledge/ideas/README.md": SHELF.format(about="Not started yet.", title="Ideas"),
            "knowledge/ideas/no-card.md": "# No card here\n",
            "knowledge/ideas/odd.md": note("A strange status.", status="current"),
            "knowledge/people/notes.txt": "not a note, and its folder has no README\n",
            "skills/README.md": "# Skills\n## The brain's own\n- [brain-spec](brain-spec/SKILL.md): the spec.\n"
                                "- [other](other/SKILL.md), [long](long/SKILL.md): two more.\n"
                                "## Copied skills\n- [copied](copied/SKILL.md): kept as it came.\n",
            "skills/brain-spec/SKILL.md": "# Spec\nLessons from using this skill in the brain: [LESSONS.md](LESSONS.md).\n"
                                          "[a task](../../knowledge/tasks/send-pack.md)\n",
            "skills/brain-spec/LESSONS.md": "# Lessons: brain-spec\n*Newest at the top.*\n\n- **19 Oct 2026:** two.\n"
                                            "- **18 Oct 2026:** one.\n",
            "skills/other/SKILL.md": "[a task](../../knowledge/tasks/send-pack.md) "
                                     "[a decision](../../knowledge/decisions/2026-10-17-older.md)\n"
                                     "```\n[an example](LESSONS.md)\n```\n",
            "skills/other/LESSONS.md": "- **21 Oct 2026:** one.\n",
            "skills/long/SKILL.md": "# Long\n" + "A step.\n" * 520,
            "skills/copied/SKILL.md": "# Copied\nSee [LESSONS.md](LESSONS.md).\n## In this brain\n",
            "skills/copied/LESSONS.md": "- a lesson.\n" * 21,
            "skills/tidy/SKILL.md": "# Tidy\nSteps.\n## In this brain\n"
                                    "Lessons from using this skill in the brain: [LESSONS.md](LESSONS.md).\n",
            "skills/tidy/LESSONS.md": "- **21 Oct 2026:** one.\n",
            "skills/ghost/SKILL.md": "# Ghost\n## In this brain\n[LESSONS.md](LESSONS.md)\n",
            "skills/plain/SKILL.md": "# Plain, with no lessons\n",
        }
        for rel, text in files.items():
            path = os.path.join(root, rel)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(text)
        self.lib = library.Library(root)

    def tearDown(self):
        self.tmp.cleanup()

    def read(self, rel):
        with open(os.path.join(self.tmp.name, rel), encoding="utf-8") as fh:
            return fh.read()

    def test_card(self):
        card = library.read_card(os.path.join(self.tmp.name, "knowledge/ventures/drivermods/order-flow.md"))
        self.assertEqual(card["about"], "How an order flows.")
        self.assertEqual(card["tags"], ["drivermods", "money"])
        self.assertIsNone(library.read_card(os.path.join(self.tmp.name, "knowledge/ideas/no-card.md")))
        self.assertEqual(library.to_date("19 Oct 2026").isoformat(), "2026-10-19")

    def test_build(self):
        changed = library.build(self.lib, quiet=True)
        self.assertIn("knowledge/tasks/README.md", changed)
        tasks = self.read("knowledge/tasks/README.md")
        self.assertIn("### Waiting on the owner\n- [send-pack](send-pack.md): Matt sends the pack. Due 23 Oct 2026. [law-office]", tasks)
        self.assertIn("### Doing\n- [build-site](build-site.md)", tasks)
        self.assertNotIn("old-job", tasks)
        self.assertIn("Finished, and not listed: 1.", tasks)
        top = self.read("knowledge/README.md")
        self.assertIn("- [tasks/](tasks/README.md): What's in flight.", top)
        ventures = self.read("knowledge/ventures/README.md")
        self.assertLess(ventures.index("drivermods/"), ventures.index("law-office"))
        decisions = self.read("knowledge/decisions/README.md")
        self.assertLess(decisions.index("2026-10-18-newer"), decisions.index("2026-10-17-older"))
        self.assertNotIn("2026-10-01-gone", decisions)
        self.assertEqual(library.build(self.lib, quiet=True), [], "a second build changes nothing")

    def test_find(self):
        self.assertEqual(library.find(self.lib, holder="owner"),
                         ["knowledge/tasks/send-pack.md: Matt sends the pack."])
        drivermods = library.find(self.lib, tag="drivermods")
        self.assertIn("knowledge/ventures/drivermods/README.md: The store.", drivermods)
        self.assertIn("knowledge/tasks/build-site.md: Build the site.", drivermods)
        self.assertEqual(library.find(self.lib, shelf="tasks", text="old job"), [])
        self.assertEqual(len(library.find(self.lib, shelf="knowledge/tasks", text="old job", show_all=True)), 1)
        self.assertEqual(len(library.find(self.lib, status="superseded")), 1)

    def test_check(self):
        problems = "\n".join(library.check(self.lib))
        self.assertIn("knowledge/people/: no README.md", problems)
        self.assertIn("knowledge/ideas/no-card.md: no card", problems)
        self.assertIn('knowledge/ideas/odd.md: status "current"', problems)
        self.assertIn('the tag "nowhere"', problems)
        self.assertIn('knowledge/tasks/bad-holder.md: holder "bob"', problems)
        self.assertIn("skills/other/SKILL.md: a skill links into the notes (../../knowledge/tasks/send-pack.md)", problems)
        self.assertNotIn("skills/brain-spec", problems)
        self.assertNotIn("2026-10-17-older.md)", problems)
        self.assertNotIn("drivermods", problems)
        self.assertNotIn("money", problems)
        self.assertNotIn('the tag "robot"', problems)
        self.assertNotIn("history", self.lib.known_tags())
        self.assertIn("skills/long/SKILL.md: 521 lines, over 500", problems)
        self.assertIn("skills/other/LESSONS.md: skills/other/SKILL.md doesn't link it", problems,
                      "a link in a code block doesn't count")
        self.assertIn("skills/copied/SKILL.md: a copied skill links LESSONS.md outside", problems)
        self.assertIn("skills/copied/LESSONS.md: 21 lessons, past 20", problems)
        self.assertIn("skills/ghost/SKILL.md: links LESSONS.md, but there isn't one", problems)
        for fine in ("skills/tidy", "skills/plain", "skills/copied/SKILL.md: 2"):
            self.assertNotIn(fine, problems)

    def test_lessons(self):
        self.assertEqual(library.own_skills(self.lib), ["brain-spec", "other", "long"])
        self.assertEqual(library.lessons(self.lib), [
            "skills/brain-spec/LESSONS.md: 2 lessons (fold in)",
            "skills/other/LESSONS.md: 1 lesson (fold in)",
            "skills/copied/LESSONS.md: 21 lessons (copied, keep short)",
            "skills/tidy/LESSONS.md: 1 lesson (copied, keep short)",
        ])

if __name__ == "__main__":
    unittest.main()
