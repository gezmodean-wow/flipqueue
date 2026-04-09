# Discord Setup Runbook

Operator-side setup for the FlipQueue Discord community. This covers the
things you have to click through in Discord and GitHub. The bot design
lives in `discord-bot-design.md`.

## 1. Server structure

Create the server and set it up with this channel layout. This is a
starting point; split or merge as volume dictates.

### Categories and channels

- **INFO**
  - `#welcome` — rules, links to Curse/Wago, quick-start
  - `#announcements` — release notifications (webhook-driven, read-only)
  - `#changelog` — optional second webhook target if you want
    announcements to stay minimal
- **COMMUNITY**
  - `#general` — chat
  - `#off-topic`
  - `#screenshots`
- **SUPPORT**
  - `#support` — users describe issues here; one thread per report
  - `#bug-reports` — confirmed bugs mirrored from GitHub via webhook
  - `#feature-requests` — separate from bugs so triage is easier
- **DEV** (private, operator + trusted testers)
  - `#dev-log` — GitHub activity webhook (commits, PRs, CI)
  - `#triage` — bot posts draft issues here for operator approval

### Roles

- `@dev` — you, full perms
- `@tester` — alpha/beta testers, pingable on pre-release builds
- `@verified` — users who have linked a GitHub account (optional,
  nice-to-have for bot write actions)
- everyone else — default

Record the `@tester` role ID once created (right-click the role with
Developer Mode enabled) — you will need it for the release notification
ping.

## 2. Release notifications (done in workflow)

The `Notify Discord` step in `.github/workflows/release.yml` posts a
formatted embed to a Discord webhook on every tag push, with the
matching section from `CHANGELOG.md` as the body. Color and label
change per channel (alpha / beta / release).

### Setup

1. In Discord: **Server Settings → Integrations → Webhooks → New
   Webhook**.
2. Name it `FlipQueue Releases`, point it at `#announcements`, copy the
   webhook URL.
3. In GitHub: **Repo Settings → Secrets and variables → Actions → New
   repository secret**.
4. Name: `DISCORD_WEBHOOK_URL`, Value: (paste the URL).
5. (Optional) Add a second secret `DISCORD_TESTER_ROLE_ID` with the
   numeric `@tester` role ID. If set, alpha/beta builds will ping that
   role. Leave unset to skip the ping entirely.
6. Push a tag to test. The workflow silently skips the notify step if
   the secret is absent, so existing behavior is preserved until you
   set it.

### How the changelog section is selected

The step runs an `awk` pass over `CHANGELOG.md` looking for a header
that matches either `## <tag>` exactly or `## <tag> <title>` (handles
the em-dash-subtitle style used for some releases). It copies everything
up to the next `## ` header and truncates to ~3900 chars to fit a
Discord embed description.

If no matching section exists in the changelog, the step posts a
fallback linking to the GitHub release page — so forgetting to update
the changelog is graceful, not an error.

## 3. GitHub activity webhook (no code)

Discord has a special endpoint that accepts GitHub's webhook payload
format directly. Use it for issues, PRs, pushes, CI status — whatever
GitHub event you want mirrored.

### Setup

1. In Discord: **Server Settings → Integrations → Webhooks → New
   Webhook**. Name: `FlipQueue GitHub`, channel: `#dev-log` (or
   `#bug-reports` if you only want issue events in the public channel —
   see below).
2. Copy the webhook URL and append `/github` to the end:
   `https://discord.com/api/webhooks/<id>/<token>/github`
3. In GitHub: **Repo Settings → Webhooks → Add webhook**.
4. Payload URL: the `/github` URL from step 2.
5. Content type: `application/json`.
6. Secret: leave blank (Discord ignores it).
7. Events: choose "Let me select individual events" and pick:
   - Issues
   - Issue comments
   - Pull requests
   - Pull request reviews
   - Releases
   - (Optional) Pushes, Workflow runs — these get noisy; only enable
     in `#dev-log`.
8. Save. GitHub sends a `ping` event; confirm it arrived in Discord.

### Splitting events across channels

If you want issues in `#bug-reports` but pushes/CI in `#dev-log`,
create two webhooks (one per channel) and two GitHub webhooks with
different event selections. GitHub supports many webhooks per repo.

## 4. Testing checklist

After setup, verify end-to-end:

- [ ] Push a throwaway tag (`v0.0.0-test1`) on a branch, confirm the
      Discord embed lands in `#announcements` with the right color and
      a fallback body (since the tag won't be in the changelog).
      Delete the GitHub release + tag afterwards.
- [ ] Open a test issue in GitHub, confirm it appears in the configured
      Discord channel.
- [ ] Close the test issue, confirm the close event also lands.
- [ ] If `DISCORD_TESTER_ROLE_ID` is set: confirm the role ping renders
      and notifies subscribed users on the next real alpha tag.
