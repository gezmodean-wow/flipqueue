# FlipQueue Discord Support Bot — Design

Status: design only, not yet implemented. Operator setup for the server
itself and the passive webhooks (releases, GitHub mirror) is covered in
`discord-setup.md`. This document is the architecture for the
interactive Claude-backed support bot that will come later.

## Goals

1. Let the operator pull a reporter's context (messages, attachments,
   screenshots) into a working Claude session without copy-pasting.
2. Triage bug reports in `#support` into draft GitHub issues that the
   operator approves before they get created.
3. Answer routine questions ("where does FlipQueue store data?", "what
   does the bank icon on the mini view mean?") by letting Claude read
   the live repo and CHANGELOG.
4. Make it cheap for the operator to ask a reporter for more info — the
   bot posts a structured follow-up template and captures responses
   back into the same Claude session.

## Non-goals

- No autonomous bug fixes or commits. Claude can *propose* patches; it
  cannot push them.
- No unsupervised posting to public channels. All writes to channels
  outside `#triage` require operator approval (reaction or button).
- Not a general-purpose chat/fun bot. The system prompt scopes it to
  FlipQueue support.
- No persistent memory of user messages beyond a thread → issue
  mapping. Discord and GitHub remain the sources of truth.

## High-level architecture

```
Discord gateway
      |
      v
  Bot process (Python, discord.py)
      |
      +-- Command router (slash commands, mentions, reactions)
      |
      +-- Session manager (per-thread state, rate limits)
      |
      v
  Claude Agent SDK (claude_agent_sdk)
      |
      v
  Claude model (sonnet-4-6 default, opus-4-6 for deep analysis)
      |
      +-- Tools (see below)
```

Single process, single machine. No queue, no worker pool — this is a
solo-dev support channel, not a SaaS. Scale if volume ever demands it.

## Components

### Discord bot process

- **Library**: `discord.py` (mature, well-documented, handles gateway
  reconnects and slash-command registration).
- **Responsibilities**:
  - Maintain gateway connection.
  - Register slash commands (`/triage`, `/ask`, `/reproduce-info`,
    `/release-notes`).
  - Listen for `@bot` mentions in whitelisted channels.
  - Download attachments (images, SavedVariables dumps, text logs).
  - Post draft issues and responses for operator approval (via button
    or reaction).
  - Enforce per-user and per-channel rate limits.

### Claude Agent SDK integration

- **Library**: `claude_agent_sdk` (Python).
- **Entry point**: `ClaudeAgentOptions` with a curated tool list and a
  FlipQueue-specific system prompt.
- **Session model**: one Claude invocation per user action. No
  long-running agent loop in the background. Context is rebuilt per
  call from Discord thread history + attachments so stale state is
  never an issue.
- **Model selection**:
  - `claude-sonnet-4-6` for routine triage, /ask, and follow-ups.
  - `claude-opus-4-6` for `/triage` with attachments, SavedVariables
    analysis, or anything the operator explicitly escalates with
    `/triage --deep`.

### Tools exposed to Claude

Each tool is a typed function registered as a custom tool via the
Agent SDK. Read-only tools run without approval; write tools return a
draft that the operator must confirm.

**Read-only**:

- `read_repo_file(path)` — read a file from a local clone of
  `flipqueue` kept in sync via a periodic `git pull` (cron, every
  few minutes, on the branch configured in the bot).
- `grep_repo(pattern, path_glob?)` — ripgrep over the local clone.
- `list_repo(path)` — directory listing.
- `read_changelog(version?)` — extract one version's section or the
  full file.
- `search_github_issues(query)` — GitHub search API.
- `get_github_issue(number)` — fetch one issue with comments.
- `fetch_thread_history(thread_id, limit=100)` — pull the last N
  messages from a Discord thread, including attachment URLs and
  author handles.
- `download_attachment(url)` — fetch an attachment and return either
  an image block (for screenshots) or the raw text (for logs /
  SavedVariables).

**Write (draft-only, require operator approval)**:

- `draft_github_issue(title, body, labels)` — return a draft; posting
  happens only after the operator reacts to confirm.
- `draft_github_comment(issue_number, body)` — same pattern.
- `draft_discord_reply(channel_or_thread_id, body)` — same pattern.

Write tools never execute directly from Claude; they return a
structured object that the bot renders as a preview in `#triage` with
accept/reject buttons. The operator is always in the loop for anything
that would be visible outside `#triage`.

### Workflows

#### `/triage` (in a `#support` thread)

1. Bot calls `fetch_thread_history` for the thread.
2. Downloads all image attachments as vision blocks, text attachments
   as inline text.
3. Calls `search_github_issues` for related reports (using keywords
   extracted from the thread).
4. Asks Claude to produce:
   - A one-paragraph problem summary
   - Reproduction steps (as gathered)
   - Suspected module (cross-referenced with `read_repo_file` /
     `grep_repo`)
   - Related existing issues
   - A draft `draft_github_issue` call
5. Bot posts the draft to `#triage` with Accept / Edit / Reject
   buttons. Accept calls the real GitHub API.

#### `@bot look at this` (in a support thread, free-form)

1. Bot pulls thread history, downloads the most recent attachment if
   the message has one.
2. Sends to Claude with a short system prompt ("help the operator
   understand this report").
3. Claude replies with analysis and, if useful, a drafted follow-up
   question (`draft_discord_reply`).
4. Operator approves the reply or edits it.

#### `/reproduce-info <template?>`

Bot posts a structured template in the current thread asking for
client version, realm, character, steps. No Claude call needed — this
is a canned message. Lives in the bot to keep the flow in one place.

#### `/ask <question>`

Short-form Q&A. Claude answers using `read_repo_file` / `grep_repo` /
`read_changelog`. Response is draft-posted to `#triage` by default;
operator can configure specific channels where `/ask` is auto-posted
without approval once trust is established.

#### `/release-notes <version>`

Claude reads the matching changelog section, drafts a friendly
announcement summary (different tone from the raw changelog),
operator approves, bot posts to `#announcements`. Complements the
automated webhook from `release.yml` — the webhook posts the raw
changelog, this produces the human-framed version.

## Safety and access control

- **Channel whitelist**: bot only responds in channels listed in its
  config. Default: `#support`, `#bug-reports`, `#triage`.
- **Write-action approval**: every tool that mutates GitHub or posts
  to a public Discord channel requires an operator confirmation.
  Implemented by having the tool return a draft object that the bot
  renders with buttons.
- **Rate limits**: per-user cap on `@bot` invocations per 10 minutes;
  global cap on Claude spend per day (configurable kill-switch).
- **No DMs**: bot ignores direct messages. Support happens in public
  threads so context is visible and reproducible.
- **System prompt scoping**: explicit instruction that Claude is a
  FlipQueue support assistant, not a general chatbot; off-topic
  requests get a polite deflection.
- **Secrets hygiene**: `ANTHROPIC_API_KEY`, `DISCORD_BOT_TOKEN`,
  `GITHUB_TOKEN` all loaded from `.env`; the bot process itself has
  no other privileges. GitHub token is a fine-grained PAT scoped to
  `flipqueue` with issues and pull-request read/write only.

## State and storage

- **SQLite DB** in `tools/discord-bot/state.db` with:
  - `thread_issues(thread_id, issue_number, created_at)` — maps a
    Discord thread to the GitHub issue it produced.
  - `rate_limits(user_id, window_start, count)`.
  - `approvals(draft_id, action, target, payload, status, operator_id)`
    — the pending-draft queue.
- No message history stored. Thread content is re-fetched from
  Discord per call.
- **Repo clone**: separate working copy at e.g.
  `tools/discord-bot/.cache/flipqueue/` updated by a background
  `git fetch && git checkout <configured ref>` on a timer. Keeps the
  bot's code view consistent even if the operator is mid-edit in the
  main checkout.

## Deployment

- **Layout**: `tools/discord-bot/` as a self-contained Python project.
  - `pyproject.toml` (uv or pdm)
  - `src/flipqueue_bot/` package
  - `config.example.toml`
  - `.env.example`
  - `README.md` with run instructions
- **Local run during alpha**: launch on the operator's dev box with
  `uv run flipqueue-bot`. No always-on hosting until volume justifies
  it.
- **Future VPS**: systemd unit template committed alongside the
  project; trivial to promote from local to hosted once stable.
- **Observability**: structured log to stdout, one line per Claude
  call with model, tool-use count, token totals. No external telemetry.

## Phasing

Roll out in three stages so each stage is usable on its own:

- **Phase A — read-only context puller**
  - Slash command `/context` that dumps thread history + attachments
    into a markdown snippet the operator can paste into their own
    Claude Code session.
  - No Claude calls from the bot itself. Pure plumbing.
  - Validates Discord/attachment handling without LLM cost.
- **Phase B — draft-only Claude**
  - `/triage`, `/ask`, `@bot` mentions call Claude and produce drafts
    in `#triage`.
  - Operator approves every write. No auto-posts.
- **Phase C — trusted auto-post**
  - After running Phase B for a while, allow specific workflows
    (e.g. `/ask` in `#support`) to auto-post without approval,
    configurable per channel.
  - Still no autonomous issue creation — human stays in the loop for
    anything GitHub-side.

## Open questions

- **Model default**: sonnet-4-6 is probably the right baseline; revisit
  once there's real usage data.
- **Screenshot handling**: vision input is straightforward for PNGs
  but SavedVariables dumps can be megabytes — truncate or sample?
- **German locale**: users are often on EU realms with German item
  names. Claude handles this fine but the GitHub issue title should
  probably be normalized to English for searchability. Leave to the
  operator to decide per-issue during triage.
- **Cost cap enforcement**: hard daily budget in USD, or message-count
  cap? Start with a simple daily message cap and upgrade if needed.
- **When the bot clones the repo**: on first run, or assume the
  operator provides a clone path? Likely easier to clone on first run
  so the bot is self-contained.

## Not building (explicitly rejected)

- A web dashboard. Discord + GitHub are the UI.
- A custom issue tracker. GitHub issues stay authoritative.
- Any kind of user-facing fine-tuning or "train on our data". All
  knowledge comes from reading the live repo and existing issues
  per-call.
- Cross-server support. Single-server, single-repo, single-operator.
