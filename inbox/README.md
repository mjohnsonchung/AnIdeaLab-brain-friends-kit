# The report inbox

Each time a brain applies a brain update, its agent writes a report of how it went (what went in, what clashed, what broke, any code it had to change) and pushes it to the brain's own repo. The brain's "Send brain update reports" workflow then sends it here, and this saves it in AnIdeaLab's private reports repo as `reports/<owner>/<repo>/<NNNN>-report.md`, so the kit gets better.

- **No key in any brain.** The workflow sends GitHub's own sign-in token for that run (OIDC, made for the audience `anidealab-brain-reports`). [api/report.js](api/report.js) checks it against GitHub's public keys, and takes the sender's repo from it.
- **Where it runs:** Vercel, from this folder (the project's root directory is `inbox`). It needs one setting, `REPORTS_TOKEN`: a fine-grained GitHub token with Contents read and write on the reports repo only.
- **Its address** is in [address.txt](address.txt), which brains read each time they send. Empty means the inbox isn't open yet, and reports wait in each brain until it is (running the workflow by hand sends them all).

## Setting it up (once)
1. **The reports repo:** a private GitHub repo, `AnIdeaLab-brain-reports`, made with a README so it isn't empty.
2. **The token:** open [this pre-filled token form](https://github.com/settings/personal-access-tokens/new?name=Brain+reports+inbox&description=Lets+the+brain+update+inbox+save+reports+in+AnIdeaLab-brain-reports&expires_in=none&contents=write). Under "Repository access" choose "Only select repositories" and pick `AnIdeaLab-brain-reports` (GitHub can't pre-fill that part), then generate it and copy it.
3. **Vercel:** add a new project, import this repo, set its root directory to `inbox`, add the environment variable `REPORTS_TOKEN` with the token, and deploy.
4. **The address:** put the project's address with `/api/report` on the end, like `https://<project>.vercel.app/api/report`, as the only line of [address.txt](address.txt), and push. Brains read it the next time they send.

A quick test that it's up: opening the address in a browser answers "This inbox takes brain update reports", and anything sent without a GitHub Actions token is turned away.
