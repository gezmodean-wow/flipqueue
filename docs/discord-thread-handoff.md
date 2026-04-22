# chronoforge-discord-mcp — design brief

**Status:** not started. Handed off from the cogworks session on 2026-04-22 after the
existing Discord MCP proved unable to create forum threads.

This doc captures what the new MCP needs to do, why the current one can't, and
enough context to start building in a fresh session without re-running the same
investigation.

## Motivation

Chronoforge uses Discord forum channels (one per cog) as the public-facing
feedback surface. The `/feedback-*` slash-command workflow writes per-issue `.md`
docs in each cog repo and cross-references Discord threads as sources. The
cogworks agent has Discord MCP configured and is the natural place to
post player-facing updates, create tracking threads, and rename/archive them as
issues move through phases.

The currently-configured `discord-mcp` server handles enough of the basics
(reading messages, posting into existing threads, server/channel/user lookups)
but is missing every primitive that involves **creating or mutating** a forum
thread — which is the common case for Chronoforge feedback work.

## Incident log (what we tried on 2026-04-22)

Posting six tracking threads for FQ-002 through FQ-007 into the flipqueue
forum channel (`1494013727295406161`):

- `send_message(channelId=<forum channel id>, message=...)` → `Channel not
  found by channelId`, despite `get_channel_info` on the same ID returning
  valid data. So the bot **can see the forum**; the tool itself is filtering.
- `create_webhook(channelId=<forum channel id>, name=...)` → same `Channel not
  found` error. Creating a webhook manually via the Discord UI on the same
  channel succeeded, confirming the channel itself accepts webhooks. The MCP
  is rejecting forum channel IDs client-side.
- `edit_text_channel(channelId=<thread id>, name=...)` to rename the
  `ledger doesn't match TSM` thread into `FQ-003: Posting prices still don't
  match TSM` → `Channel not found or is not a text channel`. Same type
  guard, now explicit in the error string.
- Granting the bot explicit per-channel permissions in the flipqueue forum
  did **not** change the outcome — expected, since the tool isn't reaching
  Discord's permission system.

Workaround used: gezmodean created five empty stub threads by hand; we
posted bodies into them as the first reply. FQ-003 was folded into a
pre-existing user thread (`1496027121112580178`) rather than a new
thread — my reply is at message
`https://discord.com/channels/1489375376760373473/1496027121112580178/1496401621163311244`.
The stubs are tedious and break the flow; hence this MCP.

## What the current MCP lacks

Root cause: `send_message`, `create_webhook`, and `edit_text_channel` all
resolve the supplied `channelId` through a local cache/resolver that only
contains `GUILD_TEXT` channels. Forum channels (`GUILD_FORUM`) and threads
inside forums (`PUBLIC_THREAD` / `ANNOUNCEMENT_THREAD`) are never in that
cache, so every call errors client-side with "not found" before a Discord
API call is made. `get_channel_info` and `list_active_threads` use different
code paths and work fine, which is why the limitation is easy to miss.

Missing capabilities:

1. Creating a forum thread (`POST /channels/{forum_channel_id}/threads`
   with an embedded initial message).
2. Editing a thread's name, archived flag, or locked flag
   (`PATCH /channels/{thread_id}`).
3. Webhook posting with `thread_name` to auto-create forum posts
   (`POST /webhooks/{id}/{token}?thread_name=...`).
4. Listing a forum's configured `available_tags` and applying them to a
   thread on creation.

## Tool surface (first cut)

```
create_forum_thread({
  channelId,           // forum channel ID
  title,               // thread name (max 100 chars)
  message,             // initial post body
  appliedTags?,        // array of tag IDs from list_forum_tags
})
→ { threadId, messageId, url }

edit_thread({
  threadId,
  name?,
  archived?,
  locked?,
  appliedTags?,        // replace the set of applied tags
  reason?,             // audit log
})
→ { threadId }

list_forum_tags({ channelId })
→ [{ id, name, emoji, moderated }, ...]

post_feedback_thread({       // Chronoforge-aware convenience wrapper
  cog,                       // "flipqueue" | "tempo" | ...
  issueId,                   // "FQ-003"
  title,                     // drawn from feedback doc frontmatter
  message,                   // post body
  status?,                   // maps to a forum tag if configured
})
→ { threadId, messageId, url }
```

The `post_feedback_thread` helper resolves `cog → forum channel id` via
`~/.chronoforge/config.json` (`cogs.<name>.discordChannelId`) so the caller
doesn't need to know channel IDs. `status` → tag mapping would be a later
enhancement; keep it optional for v1.

Nice-to-haves (not required for v1):

- `add_thread_members`, `remove_thread_members` — we don't currently need
  to manage thread membership manually.
- `pin_message_in_thread` — would be useful for long threads where the
  canonical "what we need from you" post should stay visible.
- `close_feedback_thread(issueId, resolution)` — archive + lock + post a
  signoff reply in one call, to run when `/feedback-promote --archive` fires.

## Tech stack

- Node.js 20+, TypeScript.
- `@modelcontextprotocol/sdk` for the MCP server scaffold.
- `discord.js` v14 for the Discord bindings — has first-class support for
  forum channels (`ForumChannel#threads.create`), thread editing, and
  webhook thread creation.
- `zod` for input validation on each tool (matches MCP SDK idioms).

Rough size: 200-400 LOC for v1 including all four tools and the config
loader.

## Auth / config

- Reuse the existing Discord bot token (`DISCORD_BOT_TOKEN` in the parent
  Claude Code config's MCP server entry). No new bot registration needed.
- Read `~/.chronoforge/config.json` for the cog → channel mapping. Schema
  is already stable (`cogs.<name>.discordChannelId` and
  `discord.guildId`). Don't duplicate that config inside the MCP.
- Permissions to request on the bot in Discord: `View Channel`, `Send
  Messages`, `Send Messages in Threads`, `Create Public Threads`, `Manage
  Threads` (for rename/archive), `Manage Webhooks` (only if we use the
  webhook path). Audit per-forum before publishing.

## Repo layout

Sibling to the cogs, not embedded:

```
C:/src/chronoforge-discord-mcp/
├── package.json
├── tsconfig.json
├── src/
│   ├── server.ts              # MCP server entrypoint
│   ├── tools/
│   │   ├── createForumThread.ts
│   │   ├── editThread.ts
│   │   ├── listForumTags.ts
│   │   └── postFeedbackThread.ts
│   ├── discord.ts             # discord.js client singleton
│   └── config.ts              # ~/.chronoforge/config.json loader
├── README.md
└── .mcp.json.example
```

Not a cog, not a library consumed by cogs — pure tooling. Doesn't need the
BigWigs packager / .pkgmeta / .toc dance.

## Milestones

1. Scaffold server + one tool (`create_forum_thread`) end-to-end, wired
   into Claude Code's `.mcp.json`. Verify it can post the FQ-002 drafted
   body into a brand-new thread.
2. Add `edit_thread` + backfill by renaming the `ledger doesn't match TSM`
   thread to `FQ-003: Posting prices still don't match TSM (investigating)`.
3. Add `list_forum_tags` + `post_feedback_thread`. Wire
   `/feedback-ingest` and `/feedback-ask` to call it.
4. Replace the `discord-mcp` server in `.mcp.json` (or run both side-by-side
   until the new one has parity on the read-side tools we still use).

Step 4 is where the commit to "this is the canonical MCP" happens. Until
then the existing `discord-mcp` stays configured for reads.

## Open questions for the next session

- Does the existing bot already have `Create Public Threads` +
  `Manage Threads` across every cog's forum, or does gezmodean need to
  grant per-forum? (Current test showed flipqueue forum has at least `Send
  Messages in Threads` but we didn't test thread creation directly.)
- Should `post_feedback_thread` also write the returned URL back into the
  feedback doc's `sources[]`, or leave that to the caller? Folding it in
  keeps the slash command simpler; leaving it out keeps the MCP
  general-purpose.
- Do we want to cover the cogworks, tempo, maxcraft, and tally forums at
  once, or ship flipqueue-only as v1 and scale from there?

## Reference: today's thread IDs

For sources[] updates in the flipqueue repo once this session's posts land:

- FQ-002 → `https://discord.com/channels/1489375376760373473/1496405501704142908`
- FQ-003 → `https://discord.com/channels/1489375376760373473/1496027121112580178`
- FQ-004 → `https://discord.com/channels/1489375376760373473/1496405587100041307`
- FQ-005 → `https://discord.com/channels/1489375376760373473/1496405655354081292`
- FQ-006 → `https://discord.com/channels/1489375376760373473/1496405746462494770`
- FQ-007 → `https://discord.com/channels/1489375376760373473/1496405803043782666`
