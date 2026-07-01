# Installing `ar`

This repo ships as one bundled plugin named `ar` (skills surface as `ar:notes`, `ar:synthesize`, …) inside a marketplace named `agent-resources`. Skills are inert until triggered; the `ar:using-ar` routing index is injected at session start so requests route automatically.

After install, point writes at a workspace (only needed if you are not already inside the git repo you want to write into):

    export NOTES_WORKSPACE=/path/to/your/notes-repo

Then verify: `bash skills/doctor/scripts/check.sh`.

## Claude Code

    /plugin marketplace add whacked/agent-resources
    /plugin install ar@agent-resources

Local clone instead of GitHub:

    /plugin marketplace add /path/to/agent-resources
    /plugin install ar@agent-resources

Update: `/plugin marketplace update agent-resources`. (Auto-update is off by default for third-party marketplaces; enable per the Claude Code `/plugin` Marketplaces tab.)

## Codex

    codex plugin marketplace add github:whacked/agent-resources
    codex plugin add ar

Update: `codex plugin marketplace upgrade`. *(Best-effort — verify against current Codex docs.)*

## Gemini CLI

    gemini extensions install https://github.com/whacked/agent-resources

Update: `gemini extensions update ar`. *(Best-effort — verify against current Gemini docs.)*

## OpenCode

OpenCode has no GitHub-install for skills. Clone the repo and symlink its `skills/` into a scanned path:

    git clone https://github.com/whacked/agent-resources
    ln -s "$PWD/agent-resources/skills" ~/.config/opencode/skills

(The repo also ships `.agents/skills` → `skills`, which OpenCode and standalone Codex scan if the repo itself sits in your project.) *(Best-effort — verify against current OpenCode docs.)*
