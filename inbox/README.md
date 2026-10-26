# The report inbox

Each time a brain applies a brain update, its agent writes a report of how it went (what went in, what clashed, what broke, any code it had to change) and pushes it to the brain's own repo. The brain's "Send brain update reports" workflow then sends it here, and this saves it in AnIdeaLab's private reports repo as `reports/<owner>/<repo>/<NNNN>-report.md`, so the kit gets better.

- **No key in any brain.** The workflow sends GitHub's own sign-in token for that run (OIDC, made for the audience `anidealab-brain-reports`). [api/report.js](api/report.js) checks it against GitHub's public keys, and takes the sender's repo from it.
- **Where it runs:** Vercel, from this folder (the project's root directory is `inbox`). It needs one setting, `REPORTS_TOKEN`: a fine-grained GitHub token with Contents read and write on the reports repo only.
- **Its address** is in [address.txt](address.txt), which brains read each time they send. Empty means the inbox isn't open yet, and reports wait in each brain until it is (running the workflow by hand sends them all).
