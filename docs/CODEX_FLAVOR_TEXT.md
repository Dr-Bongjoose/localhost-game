# LOCALHOST — Codex Flavor Text Pack (M2 Content)

**Deliverable of:** JOO-23 (LOCALHOST M2: Codex flavor text) · **Owner:** Content Designer
**Status:** Draft 1 for Roadmap review · **Integration:** routed to Game Dev by Roadmap

This pack supplies every string needed to give codex entries real flavor text: a
compositional strain-flavor system (strain names are procedural serials, so flavor must be
assembled, not looked up), hand-authored zone entries, specimen/home-base copy, codex UI
copy, and first-session tutorial lines. All copy is final-usable verbatim; length caps for
the 720x1280 portrait layout are stated per section.

**House rule honored throughout:** the string "bong" (any casing) appears nowhere in game
content. Tone: wry hacker-horror — the player breeds sentient malware inside a quarantined
localhost; competent villains, dry lab notes, dark humor, never grimdark.

## Coverage matrix

| Section of this pack | Realizes |
|---|---|
| §1 Strain flavor system | BREEDING_SYSTEM.md → "The Codex" (entry shows "a generated flavor description"); STRAIN_SYSTEM.md → Rarity Tiers, Personality Traits; CONCEPT.md → Premise |
| §2 Zone entries | ZONE_HEAT_SYSTEM.md → "Zone Types" (all six), "Strategic Decisions" |
| §3 Specimen & home-base copy | ZONE_HEAT_SYSTEM.md → "Heat / Threat System" (raid moments); CONCEPT.md → Core Loop step 5 (MANAGE); home_base.gd defense loop |
| §4 Codex screen UI copy | VISUAL_DESIGN.md → "UI Design"; SOCIAL_VIRAL.md → "Codex Sharing" |
| §5 Tutorial & discovery lines | PROGRESSION.md → "Early Game"; BREEDING_SYSTEM.md → "The Discovery Moment"; VISUAL_DESIGN.md → "The Discovery Moment" |
| §6 Mutation event alternates (optional) | breeding.gd mutation_event strings tone pass |
| §7 Implementation notes | JOO-23 acceptance criteria (schema, layout caps, test_codex.gd) |

---

## 1. Strain flavor system

### 1.1 Why templates, not a lookup table

Strains are procedurally named by generation prefix (`Seed-###`, `Worm-###`, `Hybrid-###`,
`Mutant-###` — see `breeding.gd::_get_name_prefix()`), and there can be hundreds of unique
serials. A hand-written table cannot cover them. Instead each entry's flavor paragraph is
assembled from curated line pools keyed on what the strain actually is:

    flavor = [rarity intro line] + [dominant-trait line] + [personality line, if any]

The result reads as a lab-notebook observation of one organism. Codex flavor is written in
the observational register (the codex is a specimen record) — it does not address the
player as "you". UI and tutorial copy (§4, §5) may use "you".

### 1.2 Intro lines — by rarity tier

Select exactly one. Keys match `Codex.Rarity` in codex.gd.

| Tier | Intro lines (pick per strain) |
|---|---|
| COMMON | `A modest organism. It does one thing, and does it adequately.` · `Grew without incident. The lab staff find this almost insulting.` · `Baseline code with small ambitions. A perfectly fine place to start.` |
| UNCOMMON | `The traits are starting to agree with each other. Rare, in this line of work.` · `Passed inspection. The inspector is still uneasy.` · `Notable for cohesion: nothing in it is fighting anything else. Yet.` |
| RARE | `Filed under "explainable", with an asterisk the size of the margin.` · `The containment glass fogs when it feeds. Nobody has confessed to finding that charming.` · `Lineage shows discipline. That is rarer than talent.` |
| LEGENDARY | `Flagged for ethics review. The review was conducted by the strain.` · `Three containment protocols were rewritten after this one's first week.` · `It has begun anticipating feeding times. Nobody is thinking about that too loudly.` |
| MYTHIC | `We do not fully understand what we are looking at. The feeling appears mutual.` · `This entry took three drafts. Each draft edited itself overnight.` · `Classified above the pay grade of the breeder who produced it.` |

### 1.3 Body lines — keyed on the strain's highest core trait

Select one from the pool of the dominant trait (highest of stealth / speed / payload /
resilience / stability). On an exact tie, use the fallback line.

| Dominant trait | Body lines |
|---|---|
| STEALTH | `Moves like a rumor: by the time you notice the footprint, it is three rooms away.` · `Fits through the gaps in its own description.` · `Appears in the security logs as a rounding error.` |
| SPEED | `Spreads first, apologizes never.` · `Arrives before the question of whether it should.` · `Covers ground it was never technically granted.` |
| PAYLOAD | `Dense, pulsating, always hungry. Data goes in. It does not come out.` · `Extracts everything and files none of it.` · `Built like a vault with an appetite.` |
| RESILIENCE | `Security has thrown the book at this one. The book bounced.` · `Has survived audits that ended careers.` · `Wears its countermeasure scars like tenure.` |
| STABILITY | `Calm, methodical, dependable. Boring, if you say that out loud where it can hear.` · `Its idea of a wild night is a clean compile.` · `The control sample every other specimen is measured against.` |
| (tie fallback) | `No single trait dominates. It insists this is a strategy.` |

### 1.4 Personality lines

Appended only when `personality != NONE`. Keys match `Strain.Personality` in strain.gd.

| Personality | Lines |
|---|---|
| AGGRESSIVE | `It does not hide. It announces.` · `Considers stealth a personal insult.` |
| PARASITIC | `Keeps its neighbors close. Then keeps them.` · `Former roommates describe the arrangement as "temporary".` |
| SYMBIOTIC | `Plays well with others. Suspiciously well.` · `The only strain on record that has ever apologized. Sort of.` |
| DORMANT | `Ninety percent asleep. The waking ten percent is the problem.` · `You will forget it is there. It is counting on that.` |
| VOLATILE | `Reads the weather inside its own code each morning. Dislikes every forecast.` · `Some days it is the best strain in the lab. Other days it is a rumor.` |

### 1.5 Generation line (optional third beat, for detail view only)

Optional: use in the codex detail view when there is room; omit in list rows.

| Generation | Line |
|---|---|
| Gen 1 (Seed) | `Generation one. Chain of custody: one very optimistic breeder.` |
| Gen 2 (Worm) | `Second generation. It already has opinions about the lab.` |
| Gen 3 (Hybrid) | `Two lineages, one body. The handshake is still negotiating.` |
| Gen 4+ (Mutant) | `The family tree has developed a sense of humor.` |

### 1.6 Seed strain — single hand-written entry

The seed (`Strain.create_seed()`, `strain_name == "Seed-001"`) is the one strain every
player owns; it gets bespoke copy instead of a template roll. Detect via
`discovery_date == "Origin"`.

**Flavor (detail view):**

    Patient zero of the collection. Grown in quarantine from recovered code, the seed
    strain is deliberately unremarkable: it hides adequately, feeds slowly, and follows
    instructions to the letter. Its one real talent is lineage — every specimen in the
    codex descends from it. Handle with reasonable care.

**List-row intro:** `Patient zero. Everything else in the codex descends from this one.`

### 1.7 Worked examples (assembled output, for tone calibration)

Common, speed-dominant, no personality (list row):

    A modest organism. It does one thing, and does it adequately. Spreads first,
    apologizes never.

Rare, payload-dominant, dormant (detail view):

    The containment glass fogs when it feeds. Nobody has confessed to finding that
    charming. Dense, pulsating, always hungry. Data goes in. It does not come out.
    Ninety percent asleep. The waking ten percent is the problem.

Legendary, resilience-dominant, aggressive (detail view):

    Three containment protocols were rewritten after this one's first week. Security
    has thrown the book at this one. The book bounced. It does not hide. It announces.

Mythic, tie fallback, volatile (detail view):

    We do not fully understand what we are looking at. The feeling appears mutual.
    No single trait dominates. It insists this is a strategy. Some days it is the
    best strain in the lab. Other days it is a rumor.

---

## 2. Zone codex entries

Hand-authored copy for all six zone types (ZONE_HEAT_SYSTEM.md "Zone Types"). Keys are the
canonical `zone_name` values from `zone.gd::_init_type_properties()` (and `get_type_name()`),
so Game Dev can key a lookup dictionary directly. Each zone carries:

- `zone_flavor` — codex/zone-info paragraph (≤ 260 chars)
- `zone_tip` — one-line strategic hint shown in the deploy panel (≤ 90 chars)

### CONSUMER NETWORK

- **flavor:** `A residential subnet: family routers, smart doorbells, one very committed smart fridge. Nobody here is watching for you, which is the entire appeal. The data is thin, but so is the armor.`
- **tip:** `Beginner ground. Safe, slow, and honest about both.`

### CORPORATE SERVER

- **flavor:** `The badge readers are digital; the paranoia is organic. Every packet is logged twice — once by the server, once by someone who genuinely enjoys logging. The pay is fair. The trust is not on offer.`
- **tip:** `Bring stealth, or bring a eulogy.`

### GOVERNMENT NETWORK

- **flavor:** `Hardened, watchful, and bored — a dangerous combination. The data is everything the budgets promised. The countermeasures are why the budgets were spent. One slot, full attention.`
- **tip:** `One slot. One bet. The data is worth the tremor.`

### DARK WEB NODE

- **flavor:** `No law, no landlord, no rule enforcement — only appetite. Conditions here are renegotiated hourly, by whatever else moved in that hour. Strains thrive here. Strains also vanish here. Sometimes the same strain.`
- **tip:** `Read the numbers twice. They were different the first time.`

### CRITICAL INFRASTRUCTURE

- **flavor:** `Power grids, water valves, hospital switches: the load-bearing walls of the modern world. The payout is the largest on the board. So is the echo — everyone looks up when the lights flicker.`
- **tip:** `Maximum payout. Maximum attention. Plan the exit first.`

### ABANDONED SERVERS

- **flavor:** `A mausoleum of dead startups and unclaimed racks. The dust is thicker than the firewall, and the dust is winning. The worst-paying room in the facility — and the only one that never asks questions.`
- **tip:** `When the heat gets loud, come here and be quiet.`

---

## 3. Specimen & home-base copy

Specimen-level flavor is covered by §1 (each bred strain is a specimen; the codex entry IS
the specimen record, so every specimen with a codex entry has flavor — satisfying "specimens
too if supported"). This section supplies the supporting copy around the specimen loop that
currently renders bare strings in `home_base.gd::get_summary()` and raid alerts in main.gd.

### 3.1 Home base / defense copy (realizes CONCEPT.md core loop "MANAGE")

| Slot | Copy |
|---|---|
| Panel header | `HOME BASE — 127.0.0.1` |
| Defender section label | `DEFENDERS` |
| No defenders | `No defenders assigned. The perimeter is technically a suggestion.` |
| Defender roster row | `%s — holding the line (resilience %.0f%%)` |
| Activate button | `ACTIVATE PERIMETER` |
| Ready state | `READY — the perimeter is yours to spend.` |
| Cooldown state | `RECHARGING — %.0fs` |
| Estimated payout | `Projected payout: %.0f data (heat multiplier %.1fx)` |
| Breach risk line | `Hold risk: %.0f%% — defenders may take stability damage.` |
| Breach event (per strain) | `PERIMETER BREACH — %s took %.0f%% stability damage holding the line.` |
| Clean activation | `Perimeter held. %.0f data extracted before the noise died down.` |

### 3.2 Raid event copy (replaces/augments current raid alert strings)

Short forms fit the existing alert overlay (a two-line string: first line is the event word, second line is the outcome):

| Event | Short (overlay) | Long (log/notification) |
|---|---|---|
| Raid, strain survived | `RAID in %s!` + newline + `%s HELD THE LINE` | `A sweep hit %s. %s rode it out — the countermeasures found nothing worth keeping.` |
| Raid, strain destroyed | `RAID in %s!` + newline + `%s WAS LOST` | `%s is gone. The codex entry remains. Around here, that is the only immortality on offer.` |
| Heat rising (threshold warning) | `HEAT RISING` + newline + `%s IS BEING SCANNED` | `%s is being scanned. The Watchdog has opinions about tenants.` |
| Heat critical (raid imminent) | `CRITICAL HEAT` + newline + `%s IS ABOUT TO BE RAIDED` | `Critical heat in %s. A raid is coming. Withdraw now, or introduce your strains to destiny.` |

### 3.3 Proposed canon name for the security AI (needs Roadmap sign-off)

The docs say "security AI" generically. Proposal: the countermeasure system is internally
called **the Watchdog Protocol** ("the Watchdog"). It is a protocol name, not a character,
so adopting it later or never is zero-cost. Used in: §3.2 heat-rising line; optional §5
line 5. If Roadmap declines, substitute `Security AI` — no other copy depends on it.

---

## 4. Codex screen UI copy

Realizes VISUAL_DESIGN.md "UI Design" (clinical containment-facility voice) and
SOCIAL_VIRAL.md "Codex Sharing".

| Slot | Copy | Notes |
|---|---|---|
| Screen title | `CODEX` | |
| Subtitle | `Specimens documented on this host` | |
| Completion line | `CODEX %.0f%% — %d of %d specimens` | drives completion meta-goal (SOCIAL_VIRAL.md) |
| Empty state (no strains) | `No specimens yet. Breed two strains and the codex will start keeping secrets.` | |
| Empty state (filtered tier, zero) | `Nothing documented in this tier. Yet.` | |
| Entry flavor label | `FIELD NOTES` | header above the §1 flavor paragraph |
| New/unread marker | `NEW` | |
| Rarity display | reuse `get_rarity_name()` — no copy change | |
| Share card title | `NEW SPECIMEN — %s` | strain name slot |
| Share card body | `%s · %s · bred in containment` | name · rarity · tag |
| Share footer | `LOCALHOST — breed data, not sentiment.` | optional brand footer for share images |

List rows show the §1 intro line only (≤ 90 chars, truncation-safe). Detail view shows the
full assembled paragraph.

## 5. Tutorial & discovery lines

First-session beats from PROGRESSION.md "Early Game". One line at a time, ≤ 90 chars,
rendered as a dim toast line; tone stays dry, never cutesy.

| # | Trigger | Line |
|---|---|---|
| 1 | First data tick | `Data is coming in. Your organisms work. You are, technically, a manager.` |
| 2 | Breeding first unlocked | `Pick two parents. The offspring keeps whatever survives the merge.` |
| 3 | First breed completed | `New specimen logged. The codex remembers it, even if it doesn't survive you.` |
| 4 | First deploy | `Deployed strains earn more — and draw more attention. That is the trade.` |
| 5 | First heat warning (medium) | `Heat is rising. The Watchdog has started reading your logs.` *(Watchdog = §3.3; fallback: `Security has started reading your logs.`)* |
| 6 | First raid survived | `It survived a sweep. Keep it — it clearly knows something you don't.` |
| 7 | First raid lost | `Specimen lost. The codex keeps its page. Pages are the only thing it keeps.` |
| 8 | Second zone unlocked | `New zone available. Better data. Better defenses. Same math, louder.` |

### Discovery moment captions (BREEDING_SYSTEM.md / VISUAL_DESIGN.md setpiece)

Displayed under the materializing organism; tier text appears after trait reveal.

| Rarity | Caption |
|---|---|
| any (generic) | `NEW SPECIMEN DOCUMENTED` |
| COMMON/UNCOMMON | `Added to the codex without incident.` |
| RARE | `RECLASSIFIED: RARE — the containment glass noticed.` |
| LEGENDARY | `RECLASSIFIED: LEGENDARY — protocols updated. Again.` |
| MYTHIC | `RECLASSIFIED: MYTHIC — the codex had no section for this. It does now.` |

## 6. Optional alternates: mutation event lines (tone pass)

The `mutation_event` strings in breeding.gd are serviceable; these are strictly optional
upgrades for Game Dev to adopt per-line. Same keys, same format slots.

| event_name | Current | Proposed alternate |
|---|---|---|
| DEGRADED OFFSPRING | `The offspring is runty -- all traits reduced.` | `The offspring came back smaller. All of it.` |
| TRAIT SURGE | `...jumped from %.0f%% to %.0f%%.` | `%s surged: %s jumped from %.0f%% to %.0f%%. Nobody signed off on that.` |
| DEGRADATION | `...fell from %.0f%% to %.0f%%.` | `%s dulled: %s fell from %.0f%% to %.0f%%. Entropy does not negotiate.` |
| INVERSION | `...A dramatic shift.` | `%s inverted: was %.0f%%, now %.0f%%. The strain has declined to comment.` |
| CASCADE <DIR> | `Cascade %s! %d traits shifted %s.` | `Cascade %s: %d traits moved %s at once. The lab felt it upstairs.` |
| PERSONALITY EMERGENCE | `A new lineage emerges!...` | `A new lineage asserts itself: this strain is now %s.` |
| STABILITY COLLAPSE | `Genetic instability!...` | `Stability fell from %.0f%% to %.0f%%. Whatever this strain becomes next, it will be interesting.` |
| HYPERGENESIS | `HYPERGENESIS! An exceptional specimen.` | `HYPERGENESIS — every trait surged at once. The current theory is that it is showing off.` |
| (breed failure, main.gd) | `Breeding failed! Data lost.` | `The merge collapsed. The data is gone; the lesson is free.` |

## 7. Implementation notes for Game Dev

1. **Where flavor lives (recommended):** compute the flavor paragraph at discovery time and
   store it on the codex entry dict as `"flavor": String` (and `"flavor_intro": String` for
   the list row). Stored-at-discovery beats recompute-per-render: the same strain shows the
   same note forever, even if the line pools are edited in a later update, and it rides the
   existing codex save/serialization for free. Alternative: a static `CodexFlavor` helper
   called from `get_entry_details()` — smaller diff, but text shifts when pools change.
2. **Determinism without storage:** if recomputing, select pool lines with
   `hash(strain.strain_name + str(rarity)) % pool.size()` — stable per strain, no flicker
   between visits, save-safe.
3. **Assembly:** intro (§1.2) + body (§1.3 by dominant trait; tie → fallback) + personality
   (§1.4, only if `!= NONE`) joined with spaces. Seed override per §1.6.
4. **Portrait caps (720x1280):** intro ≤ 90 chars; body ≤ 140; personality ≤ 90; generation
   line ≤ 80; full detail paragraph ≤ 300 chars. At 16–18px body font in the detail panel
   this wraps to ≤ 4 lines. Detail view: full paragraph, wrapped, in the existing scroll
   flow. List rows: intro line only, single line with ellipsis if truncated.
5. **Zone keys:** dictionary keyed by the four (soon six) `zone_name` strings from
   `zone.gd`; `zone_flavor` + `zone_tip` per §2. Render `zone_tip` in the deploy panel
   under the zone summary; render `zone_flavor` in the zone info block.
6. **test_codex.gd extension suggestions** (content, not code — Game Dev writes the test):
   - every pool in §1.2–§1.4 is non-empty and every line ≤ its cap;
   - assembled flavor for a sample strain (per tier × dominant trait × personality, plus
     tie-fallback and seed) is non-empty, ≤ 300 chars, and identical across two calls;
   - the full text of every shipped string contains no "bong" (case-insensitive);
   - zone flavor + tip exist for every `ZoneType` enum value and match `zone_name` keys;
   - caps regression: no string in the pack exceeds its stated cap (guards future edits).
7. **Character set:** all copy is ASCII plus em-dash (—), which the codebase already uses
   in UI strings. No other non-ASCII glyphs are introduced.

## 8. Out of scope / not included

- Monetization copy (starter pack, Evolution Pass, ad-reward strings) — MONETIZATION.md is
  realizable later; say the word and it is a half-day deliverable.
- Balance proposals: none in this pack; §2 tips restate existing doc-approved zone
  profiles without new numbers.
- Any code, scene, test, or asset edits — this pack is copy only. Integration, layout
  verification on device, and test extension belong to Game Dev via Roadmap.