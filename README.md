# Refactor

A World of Warcraft addon built for **[Ascension](https://ascension.gg)**, a custom classless WotLK 3.3.5 server — and, since its engine never assumes a fixed item database, it runs on any WotLK 3.3.5 server, including other custom realms like **[Project Ebonhold](https://project-ebonhold.com)**. Refactor scores your gear against your own stat priorities, tells you the moment an item is an upgrade, and smooths out a pile of everyday annoyances — auto-loot, quest automation, transmog collection, and more.

[![Ko-fi](https://img.shields.io/badge/Ko--fi-F16061?style=for-the-badge&logo=ko-fi&logoColor=white)](https://ko-fi.com/profetgit)

> Built first for Ascension's Conquest of Azeroth system — 21 classes × 3-4 talent specs, each with hand-tuned default stat weights — and the ten original WotLK classes besides, with the live-tooltip scanning underneath both that most gear-scoring addons skip: it never trusts an item link to say what's actually in your bag, which is exactly what a server with per-instance stat variance (Ascension's scaling, Ebonhold's random gear affixes, or anything similar) requires. See [Playing on a server other than Ascension](#playing-on-a-server-other-than-ascension) for what that means in practice.

---

## Features

### 📊 Weighted Stat Gear Comparison
The core feature. Assign your own weight to every stat (Strength, Agility, Crit, Haste, weapon DPS, etc.), and Refactor scores every item you hover or loot against what you currently have equipped.

- Instant **% upgrade / downgrade verdict** as a tooltip overlay
- Green arrows on bag items that are upgrades
- Smart slot logic — rings/trinkets/one-handers compare against your *weaker* equipped item, two-handers compare against your combined main+off hand
- **Smart equip** — right-clicking a ring/trinket/one-hander into a full pair replaces whichever equipped item is actually weaker under your weights, instead of always the first slot
- Correctly handles **per-instance item variance**: on servers where two copies of the same item link can carry different stats — Ascension's server-side scaling, Ebonhold's random gear affixes, or anything in that family — Refactor scans the *live* tooltip instead of trusting the item link, so verdicts are always accurate for the item actually in your bag, not some generic base version.
- Never guesses: if an item can't be scanned (not cached client-side, hard requirement not met, etc.), no verdict is shown rather than a misleading one.

#### Nothing here has fixed stats, so nothing is read only once

On a server like this, an item's stats belong to your copy of it, not to its name. On Ascension they follow the zone it dropped in and your level, crafted pieces roll random affixes, Worldforged gear grows with Runes of Ascension, and Mystic Enchants rewrite lines under a link that never changes; on Ebonhold, gear rolls random affixes of its own. Worse, on Ascension specifically the client will answer the first tooltip render of an item whose data has gone cold with the *base* item's numbers, then quietly correct itself a fraction of a second later — which is how a real downgrade briefly paints as a +21% upgrade.

So Refactor treats a scan as a sample, not an answer:

- **Every item instance is read repeatedly until two spaced-out scans agree** on every stat, DPS value, socket and level line before its verdict counts as final. A render that comes back looking exactly like the base item is thrown out on sight rather than scored.
- **Until then the item shows a small spinner** where its upgrade arrow goes — on bag slots, vendor and quest-reward icons, roll frames, and beside the verdict on the tooltip. The tooltip still shows its provisional percentage while checking (it's right the vast majority of the time); arrows, loot alerts and the quest reward auto-pick wait for confirmation, since those are promises rather than hints.
- **It costs less, not more.** Confirmed items are trusted three times longer than before, and a bag change no longer throws away every scan in that bag — it re-checks them a few per tick in the background instead of re-rendering a hundred hidden tooltips in a single frame.

Both halves are toggleable on the General page (or `/rfc verify` and `/rfc spinner`).

### 🏆 Class & Spec Profiles
- Auto-detects your class and primary talent spec and seeds a matching profile with community-sourced default weights the first time you log in
- Covers **both rosters**: Conquest of Azeroth's 21 custom classes (detected through Ascension's Character Advancement system) and the ten original WotLK classes — Warrior, Paladin, Hunter, Rogue, Priest, Death Knight, Shaman, Mage, Warlock, Druid — detected from the stock talent trees, with Wrath-era stat weights and the right armor-type filter for each (see [Playing on a server other than Ascension](#playing-on-a-server-other-than-ascension) if your server replaces stock talent trees with something else, like Ebonhold's Skill Tree)
- Two 3.3.5 talent trees don't say which role you play — a Feral druid is a cat or a bear, and a Death Knight tanks out of any tree — so those classes get an extra **Feral Tank** / **Tank** profile you pick yourself from the spec list; auto-detection never overrides a choice you made
- Switch, save, and manage multiple named weight profiles per character
- Auto-selection pauses if you manually switch profiles, and resumes with a simple command

### 🎁 Loot Toasts
Since Refactor auto-loots instantly (see below), the stock loot window never shows — so Refactor replaces it with animated toast popups: item icon, quality-colored name, stack count, and (if it's an upgrade) a pulsing glow with the % gain. Optionally shows the stack's auction-house value too (Auto/TSM/Auctionator, configurable on the Loot page).

### 💫 Crowd-Control Alert
The 3.3.5 client has no loss-of-control display, so it's easy to miss *why* your character suddenly stopped responding. While you're stunned, feared, polymorphed, or otherwise CC'd, Refactor shows a large center-screen icon with a cooldown spiral, a label ("Stunned", "Feared", …) and a countdown. Recognizes the CC abilities of all 21 CoA classes by spell ID, with a tooltip-text fallback that covers NPC/boss CC and, less precisely, stock-class and other-server CC (see [Playing on a server other than Ascension](#playing-on-a-server-other-than-ascension)). Movable, testable, and toggleable on the Tweaks page — roots and silences/disarms have their own sub-toggles.

### ⚙️ Quality-of-Life Tweaks
All individually toggleable:
- Fast auto-loot (no more loot window delay)
- Auto-collects transmog appearances from your bags
- Tooltip follows your cursor, with a border colored by item quality
- Auto-confirms Bind-on-Pickup loot prompts
- Quest automation — auto-accept, auto turn-in, gossip/greeting quest picking (off by default; hold **Shift** to fall back to manual for any step)
- Hides red UI error text and mutes the "I can't do that yet" error voice line
- Mutes the cast-deny **fizzle sound** (the noise when you spam an ability on cooldown or try to cast without enough resource) — needs the bundled one-click client patch, see [Installation](#installation)
- Auto-declines group invites, duels, guild invites, and trades from strangers (all off by default; hold **Shift** to handle one manually) — each decline prints a chat line so you know it happened
- Auto-accepts player resurrections in battlegrounds (off by default)
- Quick invite: Alt + Right-Click a player's unit frame, chat name, or model in the world to invite them to your party (off by default)
- Fullscreen map as a movable, resizable window instead of a fullscreen blackout (off by default)
- World map scroll-to-zoom and click-drag pan, with class-colored party/raid dots (ported from Magnify-WotLK); optional map coordinates and fade-while-moving (both off by default)
- Auto-sell gray items and auto-repair (own money only) at merchants (both off by default; hold **Shift** to skip)
- New-version notice when a guild or group member runs a newer Refactor
- Seamless bag upgrade: right-click a full bag to auto-swap in your smallest equipped bag
- Leave party when clicking Leave Dungeon at the end of an instance (off by default)

### 🖥️ In-Game Config Window
A clean, single-panel UI for everything above — no `/reload` required, changes apply instantly.

---

## Installation

1. Download the latest release (or clone this repo).
2. Copy the `Refactor` folder into your Ascension `Interface\AddOns\` directory.
3. Launch the game and make sure **Refactor** is enabled on the AddOns screen.

### Optional: mute the cast-deny fizzle sound

The fizzle noise the game plays when a cast is denied (ability on cooldown, not enough rage/mana/energy) is played by the game engine from sound files — an addon alone can't mute it. Refactor ships a tiny client patch that replaces those five sound files with silent copies:

1. Open `Interface\AddOns\Refactor\client-patch\` and double-click **`install-silent-fizzles.cmd`** (it copies a `Sound\` folder with five silent `.wav` files into your game root, next to `Ascension.exe`).
2. Restart the game.
3. Done — casts deny silently. The **"Mute cast-deny sounds"** checkbox on the Tweaks page now works as an instant in-game toggle: unticking it brings the sound back (Refactor replays a bundled copy of the original), ticking it silences again. No restart needed either way.

To undo everything, run `uninstall-silent-fizzles.cmd` from the same folder and restart the game. Without this patch installed, the checkbox has no effect while ticked (the stock sound plays as always) — and unticking it would play the sound twice, so leave it ticked.

---

## Usage

| Command | Effect |
|---|---|
| `/refactor` or `/rfc` | Open the Refactor config window |
| `/rfc rescan` | Forget every cached item scan and re-read your gear from scratch (macro-friendly) |
| `/rfc auto` | Resume automatic spec-based profile selection |
| `/rfc verify` | Toggle multi-scan confirmation of item stats |
| `/rfc spinner` | Toggle the loading animation shown while comparing |
| `/rfc debug` | Print tooltip-scan debug info on hover (sample count, agreement, confirmed/pending) |

Loot toast on/off, anchor position, and a preview toast are all on the **Loot** page of the config window.

You can also open the config window from the **minimap button** — left-click to open, right-click for a quick master toggle, drag to reposition.

---

## Screenshots

### Gear comparison tooltip
![Gear comparison tooltip](docs/images/comparison-tooltip.png)

### Bag upgrade arrows
![Bag upgrade arrows](docs/images/bag-arrows.png)

### Loot toast
![Loot toast](docs/images/loot-toast.png)

### Crowd-control alert
![Crowd-control alert](docs/images/cc-alert.png)

### Config window — General page
![Config window general page](docs/images/config-general.png)

### Config window — Tweaks page
![Config window tweaks page](docs/images/config-tweaks.png)

### Config window — Stat Weights page
![Config window stat weights page](docs/images/config-stat-weights.png)

### Minimap button
![Minimap button](docs/images/minimap-button.png)

---

## Compatibility

- Client: WotLK 3.3.5 (Interface 30300) — built for Ascension, and works on other 3.3.5 servers (see below)
- Bag addon support: works with the default Blizzard container frames, and hooks item slots directly for Bagnon, DragonUI's bundled Combuctor bags, AdiBags, and ElvUI if installed

## Playing on a server other than Ascension

Ascension is gone, and Refactor's gear-comparison engine never actually depended on it — it scans whatever tooltip the client renders and scores whatever stats it finds, with no fixed item database or Ascension-only API on its critical path. Every Ascension-specific hook (Character Advancement, `GetSpecialization`, the `ASCENSION_KNOWN_ENTRIES_*` events) is existence-checked and quietly does nothing when it isn't there. Concretely, this works out of the box on any 3.3.5 server:

- Gear scanning, scoring, tooltip verdicts, bag/vendor/quest/roll arrows, loot toasts and alerts, the hit cap, and `/rfc rescan`
- The ten original WotLK classes' default weights (Warrior, Paladin, Hunter, Rogue, Priest, Death Knight, Shaman, Mage, Warlock, Druid), auto-seeded by class the moment the stock `GetTalentTabInfo` API reports real spent points in a tree — which is how vanilla talent trees work on any standard-class server
- Manual weight profiles: `/rfc weight <stat> <value>`, `/rfc profile save <name>`, and switching between saved profiles — none of this needs auto-detection to work

What's approximate depends on how far a given server's own customizations reach:

- **Spec auto-detection** needs *some* signal that a real spec was chosen. Servers that keep the stock 3-tab talent panel give it one for free. Servers that replace talents with something else of their own (Project Ebonhold's "Skill Tree" + "Echoes" system, by its own description, has no traditional specs) likely don't — I haven't played there and can't confirm what `GetTalentTabInfo` reports on that client. If it reports nothing, a new character's profile seeds from that class's *first listed spec* as a placeholder, the same safety-net fallback that already handles a level-1 character on any server. It's one click to fix: open the Stat Weights page and pick your actual build from the spec list, or just set weights by hand with `/rfc weight` — either way, auto-detection leaves your choice alone from then on.
- **The crowd-control alert's fast path** (`RefactorCC.lua`) recognizes CC by spell ID, scraped from Ascension's own CoA class list — it won't match anything for stock classes or another server's reworked abilities. It falls back to reading the debuff's own tooltip text ("Stunned.", "Feared." at line start, which the client generates automatically for most CC), so the alert should still fire for common cases; it just won't be as fast or complete as the Ascension-tuned list.
- Any server-specific item mechanic I don't know about (unusual affix wording, a custom stat line the scanner doesn't recognize) scores at the `Unknown (scanned)` weight until you give it one of its own with `/rfc weight <name> <value>` — it's never silently dropped.

None of this has been verified against Ebonhold specifically (no server access from here) — if something doesn't detect correctly, it's very likely one of the two items above, and worth reporting so it can be tuned for real.

## Tests

The timing-dependent parts of the gear comparison (the scan-confirmation
state machine, the loading spinner) have headless tests that run against a
mock 3.3.5 client — controllable clock, scriptable tooltip renders, a frame
loop. From the addon folder, with any Lua 5.1:

```
lua5.1 tests/test_verify.lua    # scan confirmation, stale renders, spinner
lua5.1 tests/test_classes.lua   # class/spec default weights and detection
```

The `tests/` folder isn't listed in `Refactor.toc`, so it never loads in-game.

## Contributing

Issues and pull requests are welcome. If you're proposing new default stat weights for a class/spec, please explain your reasoning (source theorycraft, Pawn string, etc.) in the PR description.

## Support

If you enjoy this addon and would like to support its development, you can buy me a coffee on Ko-fi!

[![Support me on Ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/profetgit)

## License

[MIT](LICENSE) — do whatever you want with it, just keep the copyright notice.

