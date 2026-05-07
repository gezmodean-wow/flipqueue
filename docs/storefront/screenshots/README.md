# Screenshots

Project-page screenshots for CurseForge and Wago. Re-uploaded only when the UI changes materially.

## Slot order

CurseForge and Wago each support an ordered set of project images. Files in this directory should be numbered in display order:

- `01-todo.png` — main to-do view (the most-recognizable feature)
- `02-deal-finder.png` — DealFinder cross-realm pricing
- `03-characters.png` — Characters page with inventory + per-char settings
- `04-context-drawer-ah.png` — context drawer in AH mode showing scan/post rows
- `05-bank-popup.png` — bank operations popup mid-execution
- `06-mini-view.png` — mini view in default state

(Adjust as the addon evolves.)

## When to refresh

- A page got a visible UI redesign
- A feature shipped that doesn't appear in any current screenshot
- A control moved or got renamed in a way that makes existing shots misleading
- Right before tagging a public release: a quick "do these still represent what's there?" pass

Screenshots that are still accurate don't need re-uploading every release. Once they're on the project page they persist across file uploads.

## Capture tips

- 1920×1080 native, no scaling
- Default Blizzard UI scale (no compression artifacts in tooltips)
- Realistic data (real character names, real items in bags) — not the test-realm placeholder data
- A representative scenario (mid-workflow), not an empty state

## Files

*(none yet — see capture checklist below for v0.12.0 public release)*

---

## v0.12.0 capture checklist

This is the first public release populating this directory. The 6-slot order suggested in the §"Slot order" section above maps to the captures below; if you need fewer than 6, drop the lowest-priority shots first.

### Required (slot order)

1. **`01-todo.png` — To-Do page, mid-workflow**
   - Show: a real to-do list with mixed `[BUY]` / `[POST]` rows, the action-button bar visible (Clear / Rescan / Pull Bank / Buy List), at least one buy row showing the lifecycle prefix `[BUY]`. Realm and character columns populated, gold price visible.
   - Why: most-recognizable feature, sets the "this is what FlipQueue does" expectation.

2. **`02-deal-finder.png` — DealFinder cross-realm pricing**
   - Show: DealFinder page with the per-realm price grid populated, profit column sorted descending, at least one item expanded to show ilvl variants. Region selector and source dropdown visible at top.
   - Why: the single biggest "how do I find deals" answer.

3. **`03-mini-view-lifecycle.png` — Mini overlay showing the new lifecycle prefixes**
   - Show: mini overlay with at least three rows demonstrating the prefix swap — one cyan `[BUY]`, one yellow `[CHECK MAIL]`, one orange `[DEPOSIT]`. Title at top should read something like "FlipQueue - 2 to post, 1 to buy, 1 in mail, 1 to deposit".
   - Why: showcases the most player-visible v0.12.0 change. Front-loads the "this addon thinks about your workflow" pitch.
   - **NEW for v0.12.0** — required.

4. **`04-settings-tri-state.png` — Settings page with Auto/Manual/Disabled controls**
   - Show: the Settings page scrolled to the Item Management or Gold Management section, with the tri-state radio groups visible. Master switch (Manage my items / Manage my gold) at the top of the section.
   - Why: shows the "you're in control" story for players coming from addons that auto-fire too aggressively.
   - **NEW for v0.12.0** — required.

5. **`05-bank-popup.png` — Bank operations popup mid-execution**
   - Show: bank popup open with multiple sections (Pulls, Deposits, Extras, Reagents, Gold) visible, a progress bar partially filled, the per-row checkboxes with mixed checked/unchecked.
   - Why: demonstrates the "automated but transparent" angle.

6. **`06-auctionator-buylist.png` — Auctionator settings page in FlipQueue**
   - Show: the Auctionator integration page in FlipQueue with the buy-list sync settings visible (single/per-realm radio, quality/tier toggles, auto-update checkbox), and the lower section showing the live `FlipQueue - Buy` list highlighted in yellow.
   - Why: the second-biggest v0.12.0 player-visible change. Closes the "but how do I actually go shopping for the items I need to buy" question.
   - **NEW for v0.12.0** — required.

### Nice-to-have (extras if there's room)

7. **`07-characters.png` — Characters page with per-character override view**
   - Show: a row expanded to reveal the per-character action-mode overrides (the new tri-state UI applied at the character level), gold totals visible, AH cluster badges.
   - Why: explains the per-character tuning story.

8. **`08-context-drawer-ah.png` — Context drawer at the auction house**
   - Show: AH window open, FlipQueue context drawer extended on the side showing scan results / post controls. Drawer rollout in a reasonable width.
   - Why: shows AH-time integration without making it the headline.

### Capture checklist before each shot

- 1920×1080 native, no UI scaling.
- Default Blizzard UI scale (no compression artifacts in tooltips).
- Realistic data (real character names, real items in bags) — not test-realm placeholder data.
- Mid-workflow scenario — never show empty states for the headline shots.
- Hide chat frame and minimap if they crowd the focal panel; otherwise leave the WoW UI visible so the screenshot has scale context.
- For the lifecycle and settings shots, set up the scenario beforehand:
  - **Lifecycle shot**: stage one buy task at each step (browse, collect, deposit). The collect-step row only appears post-purchase, so make a small buyout immediately before capturing.
  - **Settings shot**: scroll so the master switches and at least two tri-state controls are visible together.
  - **Auctionator shot**: must have at least 3-5 buy tasks active so the *FlipQueue - Buy* list has visible content.

### Wago vs CurseForge upload notes

- Both platforms accept the same files — upload identical sets to keep them in sync.
- CurseForge: project page → "Images" tab → drag/drop in display order.
- Wago: project page → "Images" section → drag/drop in display order.
- After upload, **commit the actual image files into this directory** in the same order so the next release inherits the current state.

### After this release

When the next public release ships, do a "do these still represent what's there?" pass per §"When to refresh" above. Don't re-upload screenshots that are still accurate — they persist across file uploads on both platforms.
