# STEAL THE ARTIFACT

A Roblox multiplayer heist game built around one tight, replayable loop:

**FIND → STEAL → ESCAPE → SECURE → UPGRADE → RAID → REPEAT**

Every player owns a vault on the edge of a big, colorful city. Grab artifacts from guarded
zones (or from other players' vaults), physically carry them home while everyone tries to
bonk the loot out of your hands, and secure them on your vault's pad. Upgrade your gear and
security, display your rarest pieces, then go raid someone else.

The whole game is code: a [Rojo](https://rojo.space) project of ~24k lines of Luau. The
city, every artifact model and all UI are generated procedurally, so there are no uploaded
assets to manage.

---

## Quick start

1. Install [Rojo](https://rojo.space/docs/v7/getting-started/installation/) 7.x and its
   Studio plugin.
2. From this folder run `rojo serve`, open a new Baseplate in Roblox Studio and click
   **Connect** in the Rojo plugin. (Or build a place file: `rojo build -o StealTheArtifact.rbxl`.)
3. In **Game Settings**:
   - **Avatar → Avatar type: R15** (emotes and the ragdoll are tuned for R15; R6 works too).
   - **Places → Max players: 12** (one vault plot per player).
   - **Security → Enable Studio Access to API Services** if you want saving in Studio.
     Without it, the game automatically uses an in-memory store and everything still works.
4. Press **Play**. The server generates the city (~4,600 parts) in about a second.

To test multiplayer interactions (bonks, raids), use **Test → Clients and Servers** with
2-4 players.

### Before publishing

- Fill in your Game Pass and Developer Product ids in
  [`src/shared/Config/Monetization.luau`](src/shared/Config/Monetization.luau). Anything left at
  `0` shows as "Coming soon" and cannot be bought.
- Optionally replace the built-in sound ids in [`Sounds.luau`](src/shared/Config/Sounds.luau)
  with your own audio and add music tracks (`MusicCalm`, `MusicEvent`, `MusicChase`).
- Add your promo codes to [`src/server/Private/Codes.luau`](src/server/Private/Codes.luau)
  (server-only, never replicated).
- Private servers: enable them in **Game Settings → Monetization**. No code changes needed.

---

## Gameplay

| Loop step | How it works |
|---|---|
| **Find** | Artifacts spawn at randomized points in 7 zones. Higher-rarity loot glows, sparkles and shoots a light pillar into the sky so you can spot it from far away. |
| **Steal** | Hold the prompt. Rarer items take longer to grab; Sticky Gloves and Quick Hands make it faster. Stealing rare loot in guarded zones trips the zone alarm. |
| **Escape** | You must physically carry loot home. Weight slows you down, Legendary+ makes you glow for the whole server, guards chase you, players bonk you, lasers zap you. Getting hit knocks your best piece loose; dying drops everything. Dash, hatches to the Underground and the ring road help you get away. |
| **Secure** | Step on the glowing SECURE pad inside your vault. You get instant cash, XP, collection credit and a cinematic payout. |
| **Upgrade** | Gear (backpack, sneakers, gloves), vault pedestals and storage, and six security tracks: doors, lasers, cameras, traps, guards and alarms. |
| **Raid** | From level 5, crack another player's vault door (it trips their alarm), slip past their security and steal from their display pedestals. |

### Zones (the map)

| Zone | Flavor | Odds |
|---|---|---|
| 🏪 **Central Marketplace** | Safe social hub: the Fence, Gear Shop, Drip Shop, Quest Board, Collection, Code Machine, daily chest, leaderboard walls and a fountain with a giant spinning diamond. | Commons for new players |
| 🏛️ **Grand Artifact Museum** | Display cases, a laser-filled Gem Wing, a dinosaur skeleton, rotunda centerpiece, cameras and security guards. | Uncommon to Legendary |
| 🧪 **Abandoned Laboratory** | Wrecked lab with specimen tubes, flickering lights, toxic puddles, a laser-locked containment room and robot guards. | Uncommon to Legendary |
| 🗿 **Ancient Temple** | Stepped pyramid inside a real water moat, a hidden chamber with spike traps and golden energy beams, mummy guards. | Rare to Mythic |
| 📦 **Military Warehouse** | Container maze, searchlight watchtowers, shelf racks and a laser-caged armory. | Common to Legendary |
| 🕳️ **Secret Underground** | Glowing crystal caves under the city, reached through three hatches. Sticky mud and crystal spikes, no guards. One wall isn't real... | Rare to SECRET |
| 🏦 **High-Security Vault** | A fortress whose giant round door only opens every 3 minutes. Sweeping lasers, cameras and elite guards. An emergency vent lets trapped thieves escape. | Epic to SECRET |

Twelve vault plots form a ring around the city, linked by a ring road.

### Rarities

Common → Uncommon → Rare → Epic → Legendary → Mythic → **SECRET**. Each tier adds more
effects (sparkles, glow, swirls, light pillars, pulse rings, rainbow cycling), a longer
steal, more carry weight and louder announcements. Artifacts can also roll **Shiny** (2×
value) or **Rainbow** (5× value) mutations.

There are 71 artifacts. The 8 SECRET ones have unique effects while carried or displayed:
the Rubber Chicken of Destiny honks your position to everyone, the Banana of Doom drops
slippery peels behind you, Pocket Sun lights up Blackouts, ERR_404 glitches you in and out,
the Void Egg vacuums up dropped loot, Grandma's Cookie Jar heals you, the Dev's Keyboard
rains code, and the Crown of the First Thief boosts your whole vault's income.

### Vault security

| Track | Effect |
|---|---|
| 🚪 Door | 2.5s → 14s to crack. Cracking always trips the owner's alarm. |
| 🔴 Lasers | Up to 6 beams that blink, sweep or go chaotic. A zap stuns and knocks loot loose. |
| 📹 Cameras | Sweeping view cones (you can see the spotlight) that mark raiders and alert the owner. |
| 🍌 Traps | Banana peels (ragdoll slip), spring pads (launch raiders back out the door), glue. |
| 👮 Guards | NPC guards that patrol your vault and tackle intruders. |
| 🚨 Alarm | Longer marks, door lockdown, raider slowdown, bounties for anyone who bonks your raider, citywide alerts. |

Fairness rules: a **Rookie Shield** until level 5, a **raid shield** after every successful
raid, **home advantage** (you can't be bonked inside your own vault), a **revenge bonus** for
raiding whoever just robbed you, and **insurance** that returns unclaimed stolen loot to its
owner. Only displayed artifacts can be raided; storage is safe.

### Progression

- Cash, XP and levels, with level-up rewards and Gems every 5 levels.
- Rebirth (from level 20) resets cash, level and gear for Prestige Tokens and a permanent
  +20% cash / +10% XP per rebirth. Vault, artifacts, security, cosmetics and collection are kept.
- 9 permanent Perks bought with Prestige Tokens, and 8 prestige ranks shown on name tags.
- 3 personal **Missions**, 3 **Daily Challenges** shared by every player on the same UTC day
  (plus a bonus), 37 **Achievements** with Gem rewards and cosmetic titles, a 7-day
  **daily reward** streak and a **Collection Book** with set rewards.
- Passive income from displayed artifacts, so your vault grows while you raid.

### Viral moments

- **Global announcements** in every server (MessagingService) when someone steals a
  Legendary, Mythic, SECRET or Rainbow artifact.
- A non-blocking **steal cinematic** for rare grabs (sunburst, spinning 3D artifact, rarity
  slam, confetti), and burst effects for everyone nearby.
- **Funny fails**: ragdolls, BONK! stamps, banana slips, spring launches, zaps and guard
  tackles, each with random captions, plus dizzy stars and speech-bubble guard barks.
- A live **steal / bonk / raid feed**, hot-loot beacons, WANTED / MARKED highlights and bounties.
- **Server events** every 7-10 minutes: Artifact Rain, Golden Hour, Blackout, Meteor Strike,
  Guard Strike, Low Gravity, Black Market and Vault Breach.
- **Leaderboards** for Richest, Best Vault, Most Steals and Rarest Collection (global and
  per-server, in the UI and on walls in the Marketplace).
- A hidden secret room and hidden achievements to rumor about.

### Monetization (cosmetic only)

| What | Gives |
|---|---|
| 💎 Gem packs (Developer Products) | Gems, which only buy cosmetics. Gems are also earned from achievements, daily rewards, challenges and collection sets. |
| 👑 VIP pass | Gold name tag, VIP trail / aura / vault skin, +10 Gems per daily reward. |
| 🧳 Cosmetic Locker+ | 8 outfit loadouts (instead of 2) and 8 emote slots (instead of 4). |
| Private servers | Enabled in Game Settings. |

Cosmetics: 9 trails, 8 auras, 9 vault skins, 7 emotes, earnable titles and saved outfits.

**Robux never buys Cash, XP, levels, artifacts, backpack space, speed, steal speed, security,
shields, perks or rebirths.** There is no code path from a purchase to any of those, and
`tests/run.luau` checks that no cosmetic carries a gameplay field.

### UI

Inventory, Vault, Upgrades (gear, rebirth, perks), Shop, Quests (missions, daily,
achievements), Collection Book, Leaderboards, Daily Rewards, Codes and Settings, plus a
HUD with animated cash, XP bar, event timer, backpack slots, action buttons with cooldowns,
status chips, an off-screen waypoint arrow home, raid alerts, toasts, banners and a guided
first session.

The layout is authored at 1280×760 and scaled for phones, tablets, PCs and TVs.

| | PC | Console | Mobile |
|---|---|---|---|
| Steal / interact | E | X | Tap prompt |
| Bonk | F (or click in shift-lock) | RT | 👊 button |
| Dash | Q | RB | 💨 button |
| Go home | R | Y | 🏠 button |
| Emote wheel | G | D-pad ↓ | 😀 button |
| Menus | B V U N J K L Y H P | D-pad ↑, B to close | Sidebar |

Settings include music and SFX volume, low VFX mode for older phones, camera shake,
feed / global announcement toggles and a **reduce flashing** accessibility option.

---

## Architecture

```
src/
  first/       ReplicatedFirst  - branded loading screen
  shared/      ReplicatedStorage.Shared
    Config/    every tunable: rarities, artifacts, zones, upgrades, security, quests,
               achievements, cosmetics, monetization, events, sounds
    Net.luau             single registry of every remote
    Progression.luau     pure formulas used by BOTH server (authoritative) and UI (previews)
    ArtifactModels.luau  procedural models for world, displays, carried loot and UI previews
    SecurityPatterns.luau  deterministic laser / camera motion
  server/      ServerScriptService.Server
    Main.server.luau     boots services (Init, then Start, in a fixed order)
    RequestRouter.luau   the only client -> server request entry point
    PromptGuard.luau     validates ProximityPrompt holds
    GameEvents.luau      server event bus (quests / achievements listen here)
    Map/                 procedural city builders
    Services/            25 services (data, economy, carry, artifacts, plots, security,
                         guards, combat, raids, quests, events, leaderboards, shop, ...)
    Private/Codes.luau   promo codes (server-only)
  client/      StarterPlayerScripts.Client
    Main.client.luau     boots controllers
    Controllers/         data mirror, UI, HUD, effects, world animation, input, ...
    UI/                  theme, component kit, 3D previews, 10 windows
tests/         headless Lune test suite
```

### Security model

The server owns every outcome. Clients only *ask*.

- **Requests** go through `RequestRouter`: per-player, per-action token-bucket rate limits,
  argument validators (types, ranges, lengths), and handlers wrapped in `pcall` that always
  return `{ ok, msg, data }`. All prices, ownership checks and rewards are computed on the
  server from shared config.
- **Stealing / cracking / hatches** use ProximityPrompts validated by `PromptGuard`: the server
  records `PromptButtonHoldBegan` and rejects triggers that come too early, from too far
  away, or from a dead or stunned player. This defeats instant-trigger exploits.
- **Combat**: the client sends "I swung" with an optional target hint. The server enforces the
  cooldown, picks a valid target in front of the attacker within range, and applies safe-zone
  and home-advantage rules, damage and drops.
- **Loot never exists in two places**: every artifact has a unique id and moves synchronously
  between world, backpack (server memory) and vault (saved data). A raided artifact leaves the
  victim's data the moment it's grabbed, and the victim is saved soon after.
- **Movement**: a lenient speed check on loot carriers stops teleport-home exploits;
  server-initiated teleports, knockbacks and dashes get grace windows. Vault interiors and the
  High-Security Vault push out anyone who didn't come through an open door (anti-noclip).
- **Saving**: session-locked DataStore saves using `UpdateAsync`. Saves refuse to overwrite if
  another server has taken the session, so server hopping can't duplicate items. Autosave,
  save on leave, `BindToClose` flush and retries are built in. Robux receipts are recorded and
  saved before Roblox is told the purchase was granted.
- Promo codes and receipts are never replicated to clients.

### Performance and streaming

- `StreamingEnabled` with atomic models for artifacts and guards. Client visuals attach when
  things stream in (CollectionService tags) and clean up when they stream out.
- Lasers and cameras never move on the server. Both sides evaluate the same time-based
  patterns, so devices cost no replication bandwidth and stay in sync with hit detection.
- Artifact bobbing, rainbow cycling, flickering lights, alarm lights and mood lighting are
  all client-side. World VFX use an `UnreliableRemoteEvent` and only go to nearby players.
- Data replication is batched per frame and per key.
- Low VFX mode cuts particles for older devices.

---

## Tuning

Almost everything a designer wants to change lives in `src/shared/Config`:

- `GameConfig.luau`: movement, carry weight, combat, raid rules and shields, economy rates,
  mutations, event timing, plot ring, autosave, vault door cycle.
- `Artifacts.luau`: names, values, zones, shapes, colors, flavor text, SECRET effects.
- `Zones.luau`: rarity odds per zone, active spawn counts, respawn timers, guard counts.
- `Upgrades.luau` and `Security.luau`: costs, growth and per-level stats.
- `Quests.luau`, `Achievements.luau`, `DailyRewards.luau`, `Events.luau`, `Cosmetics.luau`.

Set `GameConfig.Debug.StudioStartingCash` or `StudioFastEvents` for faster testing in Studio.

---

## Development checks

```bash
# Type-check against the Roblox API (luau-lsp + Roblox type definitions)
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --platform=roblox --sourcemap=sourcemap.json \
  --definitions=@roblox=globalTypes.d.luau src

# Format
stylua src tests

# Headless tests: every module loads, config integrity, all 71 models build,
# progression math, and the entire city generates with valid Instance properties
lune run tests/run
```

`globalTypes.d.luau` comes from the luau-lsp repo (`scripts/globalTypes.d.luau`).

## Notes and next steps

- Visuals are built from primitives so the project needs no uploads. For extra polish, swap
  in meshes and decals. `ArtifactModels.luau` and the map builders are the only places to change.
- NPC guards use Roblox's default R6 walk and idle animations. Emotes use Roblox's default
  R15 and R6 emote animations, which any experience can play.
- Default sounds are the ones built into the Roblox client. Add music ids in `Sounds.luau`.
