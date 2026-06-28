# LOCALHOST - Breeding System Design

## Overview

Breeding is the heart of the game. You select two parent strains and attempt to combine them. This is the core addiction loop and the primary source of strategic depth.

## How Breeding Works

1. Select two parent strains from your collection
2. Offspring inherits a random mix of parents' core traits, weighted toward the stronger parent
3. Chance for mutation -- random trait changes that can be beneficial or harmful
4. Personality traits can blend or conflict (e.g., aggressive + symbiotic = unpredictable)
5. Low-stability parents increase mutation chance
6. Breeding has a cooldown timer (or costs resources) to prevent infinite instant breeding

## Risk Mechanics

- BREEDING CAN FAIL: Both parents are consumed and you get nothing. Base failure rate is low but increases with rare/unstable combinations
- DEGRADED OFFSPRING: Result can be worse than both parents
- MUTANT: Rare outcome -- a strain with a trait combination that doesn't exist in the normal pool. These are the exciting discoveries

## Risk Mitigation (Monetization Entry Points)

- Breeding insurance (premium currency) -- protects parents from destruction on failure
- Stability boosters (earned currency) -- temporarily raise a strain's stability for one breed
- Breeding chamber upgrades -- reduce failure rate permanently

## The Discovery Moment

When breeding produces a new strain, the game pauses for a discovery sequence:
1. The organism materializes in your containment view (dark space)
2. You see it for the first time -- its visual appearance
3. Traits are revealed one by one
4. If it's a mutation or rare type, the moment is more dramatic

This is the screenshot moment. This is what players share. "I bred this unholy thing and it's gorgeous."

## The Codex

A collection/bestiary of every strain you've ever bred. Like a Pokedex for malware organisms.

Each entry shows:
- The strain's visual representation
- Its full trait list
- Its discovery date
- How many times you've bred it
- A generated flavor description

Codex categories:
- Common strains (easily bred)
- Uncommon strains (specific trait combinations)
- Rare strains (specific mutations)
- Legendary strains (extremely rare mutations with unique properties)
- Mythic strains (only obtainable through special events or extremely lucky breeding)

Codex completion is a major meta-goal. Players want to discover every strain type.