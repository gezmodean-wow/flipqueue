# FlipQueue - Claude Code Instructions

## Permissions
- Allowed to create, edit, and delete files in this repo without confirmation
- Allowed to run git commands (commit, push, branch, etc.) without confirmation
- Allowed to run `gh` CLI commands (create repos, PRs, issues) in the `gezmodean-wow` org
- Allowed to create/modify files in `C:\src\flipqueue\` and subdirectories
- Allowed to read files in WoW AddOns directory for reference: `C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\`
- Allowed to run lua syntax checks and file operations without asking

## Project Context
- WoW addon (Lua, .toc) for The War Within (Interface 120001)
- GitHub org: `gezmodean-wow` (private)
- Repo: `gezmodean-wow/flipqueue`
- Local path: `C:\src\flipqueue`
- WoW symlink: `C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\flipqueue` -> `C:\src\flipqueue`
- SavedVariables: FlipQueueDB (account-wide)

## Coding Conventions
- All Lua files use `local addonName, ns = ...` for namespace
- Colors defined in Core.lua ns.COLORS table
- Use WoW native templates (BasicFrameTemplateWithInset, GameMenuButtonTemplate, etc.)
- No external library dependencies (no Ace3, no LibStub)
- Item key format: `itemID;bonusIDs;modifiers` (matches FlippingPal)

## User Preferences
- Keep last character slot as "flex slot" for temp characters on sell realms
- German EU account - item names and realm names may be in German
- Uses FlippingPal.com + TSM + Auctionator for cross-realm arbitrage
- Prefers clean TSM-like UI styling (tabular data, sortable columns, side navigation)
