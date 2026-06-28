# LOCALHOST - Development Roadmap

## Development Workflow

- Primary development on Linux dev machine (Godot installed here, I can write/test code directly)
- User syncs project to MacBook Pro M1 via git for learning and experimentation
- User time budget: ~5 hours/week
- User learning goal: become able to write own code through building games together
- Approach: I write code with heavy comments, user learns by reading, modifying, and experimenting

## Phase 1: THE CORE (Weeks 1-4) -- Must ship to have a game at all

- [ ] Set up Godot 4 project structure
- [ ] One screen showing one strain generating data over time
- [ ] Strain data model (traits, stats, data generation)
- [ ] Basic breeding interface (combine two strains to make a new one)
- [ ] Strain traits that actually affect data generation
- [ ] 3-4 zone types to deploy strains into
- [ ] Basic heat system that rises and falls
- [ ] A codex screen showing strains you've discovered
- [ ] Core loop: earn, breed, deploy, manage heat

No monetization. No battle pass. No leaderboards. No cosmetics. No mutations yet.
Test: Is the core loop FUN? If yes, everything else is layers on top.

## Phase 2: THE DEPTH (Weeks 5-8)

- [ ] Mutations and rare strain types
- [ ] The discovery moment with visuals
- [ ] More zone types (all 6 types)
- [ ] Breeding risk mechanics (failure, degraded offspring)
- [ ] Strain personality traits
- [ ] Heat countermeasures and strategic depth
- [ ] Codex with full entries and flavor text
- [ ] Strain visual generation (procedural organism visuals)

## Phase 3: THE BUSINESS (Weeks 9-12)

- [ ] Premium currency system
- [ ] Rewarded ads integration
- [ ] Starter pack offer
- [ ] Battle pass / Evolution Pass
- [ ] Cosmetic themes (lab + strain display)
- [ ] Leaderboards (total data, unique strains, zones controlled, legendaries)
- [ ] Codex sharing (generated shareable images)
- [ ] Weekly challenges
- [ ] Android export and store preparation

## Phase 4: POST-LAUNCH (ongoing)

- [ ] Seasonal events with limited-time strains and zones
- [ ] Guilds / syndicates (cooperative play)
- [ ] New strain categories
- [ ] New zones
- [ ] Content updates based on player data
- [ ] Balance patches

## Tech Stack

- Engine: Godot 4
- Language: GDScript (Python-like)
- Version control: Git (GitHub)
- Platform: Android
- Dev machines: Linux (primary dev) + MacBook Pro M1 (learning/testing)
- No physics engine needed
- No real-time multiplayer
- No 3D models or animation rigs
- Core gameplay is UI, numbers, timers, and 2D organism visuals