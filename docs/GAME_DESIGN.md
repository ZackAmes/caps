# CAPS - Game Design Document

## 1. Overview

CAPS is a fully on-chain, community-driven tactical board game. Players command squads of "Caps" (pieces/units) on a 3×7 grid, competing to destroy the opponent's Tower or eliminate all their units. The game draws inspiration from tactical RPGs, tower defense, and collectible card games, with a unique community governance layer that gives players direct control over the game's evolution.

**Tagline:** *Command. Conquer. Create the meta.*

---

## 2. Core Vision

### 2.1 Design Pillars

1. **Strategic Depth, Simple Rules** — Easy to learn, impossible to master. Every decision matters.
2. **Community Ownership** — Players vote on balance changes, new sets, and ban lists via governance tokens.
3. **On-Chain Purity** — All game state lives on-chain. No hidden information, no server authority.
4. **Expressive Play** — Rich tactical space through unit variety, board positioning, and energy economy.

### 2.2 What Makes CAPS Different

- **Governance-Driven Meta:** Unlike traditional TCGs where developers control balance, CAPS players vote on changes.
- **Custom Playlists:** Anyone can create custom rule sets, ban lists, and map layouts.
- **Track-Based Movement:** Inspired by *Pokémon Duel*, pieces move along lanes with surround-capture mechanics.
- **Simultaneous Resolution:** Commit-reveal system for faster gameplay on-chain.

---

## 3. Core Mechanics

### 3.1 Board

- **Dimensions:** 3 columns × 7 rows
- **Orientation:** Player 1's base at row 0, Player 2's base at row 6
- **Lanes:** 3 vertical tracks. Pieces generally move forward along their lane.
- **Special Tiles:**
  - **Tower Tiles:** (row 0, col 1) and (row 6, col 1) — the objective
  - **Speed Tiles:** Certain tiles grant +1 movement when crossed
  - ** choke Points:** The center row creates natural confrontation zones

### 3.2 Pieces ("Caps")

Each player starts with **6 Caps**:
- **1 Tower** (immobile, must be defended)
- **5 Units** (varied by set/deck choice)

#### Cap Properties

| Property | Description |
|----------|-------------|
| `name` | Display name |
| `health` | Max HP |
| `attack` | Base damage |
| `move_range` | (x, y) movement limits |
| `attack_range` | Relative positions that can be attacked |
| `ability` | Special power with unique effect |
| `ability_range` | Range of ability targeting |
| `ability_cost` | Energy to activate |
| `play_cost` | Energy to deploy from bench |
| `move_cost` | Energy per move action |
| `attack_cost` | Energy per attack action |

### 3.3 Cap Archetypes

| Archetype | Role | Movement | Combat Style | Example |
|-----------|------|----------|--------------|---------|
| **Tower** | Objective | Immobile | Low damage, high HP | *Fortress* — must survive |
| **Basic** | Generalist | Balanced | Moderate all-around | *Knight* — moves 2, attacks adjacent |
| **Elite** | Specialist | Varies | High damage or utility | *Berserker* — self-damage for big attacks |
| **Mage** | Support | Fast/Long | Low attack, strong abilities | *Healer* — restores ally HP |
| **Mythic** | Legendary | Unique | Game-changing power | *Dragon* — area damage aura |

### 3.4 Turn Structure

```
Turn Start
├── Phase 1: Energy Generation
│   └── Base: 3 energy + 1 per surviving non-tower cap
│   └── Max cap: 10 energy
├── Phase 2: Action Sequence (spend energy)
│   └── Actions (in any order, until out of energy or passes):
│       ├── Deploy — Play cap from bench to board (play_cost)
│       ├── Move — Relocate cap (move_cost × distance)
│       ├── Attack — Deal damage to enemy in range (attack_cost)
│       ├── Ability — Activate special power (ability_cost)
│       └── Retreat — Return cap to bench (free, ends turn)
├── Phase 3: Resolution
│   └── Apply end-of-turn effects (burn, heal over time, etc.)
└── Phase 4: Check Win
    └── If tower destroyed OR all enemy caps eliminated → WIN
```

**First Turn Advantage Mitigation:**
- Turn 0 (P1): 1 action max, 2 energy
- Turn 1 (P2): 1 action max, 3 energy
- Turn 2-3: 2 actions max
- Turn 4+: 4 actions max

### 3.5 Energy Economy

- Energy does **NOT** carry over between turns (use it or lose it)
- This creates urgency and prevents turtling
- Player must choose: many small actions or few big ones

### 3.6 Surround & Capture

If an enemy cap is **adjacent to 2+ of your caps** (orthogonal), you may spend 2 energy to **send it back to bench** (not kill — can be redeployed). This creates tactical pincer opportunities and punishes overextension.

---

## 4. Win Conditions

1. **Primary:** Destroy opponent's Tower (reduce to 0 HP)
2. **Secondary:** Eliminate all opponent's Caps (they cannot deploy from empty bench)
3. **Timeout:** After 50 turns, player with more total cap HP remaining wins

---

## 5. Set System

### 5.1 Concept

Like Magic: The Gathering sets or Hearthstone expansions, new Caps are released in **Sets**. Each Set introduces:
- **4-8 new Cap types** with unique mechanics
- **1-2 new board layouts** (optional)
- **Theme:** e.g., "Cyber Set" (tech-themed), "Nature Set" (growth/summon mechanics)

### 5.2 Set Lifecycle

```
Set Proposal → Community Vote → Art & Design → Testnet Period → Mainnet Release
```

### 5.3 Rotation

- **Standard Playlist:** Latest 4 sets + core set
- **Wild Playlist:** All sets ever released
- **Custom Playlists:** Community-defined (see §8)

---

## 6. Community Governance

### 6.1 Governance Token: $CAPS

- Earned by playing matches, winning tournaments, contributing to the ecosystem
- Used to vote on proposals

### 6.2 Proposal Types

| Type | Description | Threshold |
|------|-------------|-----------|
| **Balance Patch** | Stat changes to existing caps | 5% of circulating supply |
| **Ban List Update** | Ban or unban specific caps in Standard | 3% of circulating supply |
| **New Set** | Approve a proposed set for development | 10% of circulating supply |
| **Rules Change** | Modify core mechanics (energy, board size, etc.) | 15% of circulating supply |
| **Emergency Patch** | Hotfix for exploits (fast-tracked) | Core team + 5% |

### 6.3 Voting Mechanics

- **Quadratic voting** to prevent whale dominance
- **Vote-locking:** Tokens are locked for the voting period + 7 days
- **Delegation:** Players can delegate voting power to trusted community members

### 6.4 Reputation System

Beyond tokens, players earn **reputation** for:
- Accurate balance predictions (voting with the eventual winning side)
- Quality set proposals that pass
- Tournament performance
- Bug/exploit reports

---

## 7. On-Chain Architecture

### 7.1 Design Constraints

- **Turn-based:** Each move is a transaction (~2-5s on Starknet)
- **Perfect information:** All state visible on-chain
- **Computation limits:** Keep move resolution under gas limits

### 7.2 Data Model (Dojo ECS)

```cairo
// Core Models
struct Game {
    id: u64,
    player1: felt252,
    player2: felt252,
    caps_ids: Array<u64>,
    turn_count: u8,
    over: bool,
    effect_ids: Array<u64>,
    last_action_timestamp: u64,
}

struct Cap {
    id: u64,
    owner: felt252,
    location: Location,  // Bench | Board(Vec2) | Hidden | Dead
    set_id: u64,
    cap_type: u16,
    dmg_taken: u16,
    shield_amt: u16,
}

struct CapType {
    id: u16,
    name: ByteArray,
    stats: CapStats,
    attack_range: Array<Vec2>,
    ability_range: Array<Vec2>,
    ability_target: TargetType,
}

struct Effect {
    game_id: u64,
    effect_id: u64,
    effect_type: EffectType,
    target: EffectTarget,
    remaining_triggers: u8,
}
```

### 7.3 Action System

Players submit an **array of Actions** per turn (batch transaction):

```cairo
enum Action {
    Deploy { cap_id: u64, x: u8, y: u8 },
    Move { cap_id: u64, direction: u8, amount: u8 },
    Attack { cap_id: u64, target_x: u8, target_y: u8 },
    Ability { cap_id: u64, target_x: u8, target_y: u8 },
    Retreat { cap_id: u64 },
    Surround { cap_id: u64, target_id: u64 },
}
```

### 7.4 Commit-Reveal (Optional Variant)

For competitive play, actions can be submitted as hashes first, then revealed simultaneously to prevent sniping.

---

## 8. Custom Playlist System

### 8.1 Concept

Anyone can create a **Playlist** — a custom game mode with self-defined rules:

### 8.2 Playlist Parameters

```typescript
interface Playlist {
  name: string;
  creator: string;
  allowed_sets: u64[];        // Which sets are legal
  banned_caps: u16[];         // Specific cap bans
  board_layout: BoardLayout;  // Standard, alternate, or custom
  energy_rules: EnergyRules;  // Custom energy generation
  win_conditions: WinType[];  // Which win conditions apply
  turn_timeout: u64;          // Seconds per turn
  ranked: boolean;            // Affects rating/MMR
}
```

### 8.3 Featured Playlists

- **Standard:** Official balance, latest sets
- **Wild:** Everything allowed
- **Draft:** Pick caps from random pool
- **Beyond the Bridge:** Single-lane variant (1×7)

### 8.4 Discovery

- Playlists sorted by active players
- Community ratings
- Tournament-sponsored playlists

---

## 9. Client Architecture

### 9.1 Tech Stack

- **Frontend:** Svelte 5 + TypeScript + Vite
- **3D Rendering:** Threlte (Three.js for Svelte)
- **On-Chain:** Dojo Engine SDK + Starknet.js
- **Wallet:** Cartridge Controller (passkey auth)

### 9.2 Client Responsibilities

1. **Render** board state from on-chain data
2. **Validate** moves locally before submitting (UX feedback)
3. **Animate** actions as they resolve on-chain
4. **Queue** custom playlists and matchmaking

### 9.3 Why No WASM Simulation

Removed in favor of:
- **RPC simulation:** Call `simulate_turn()` on the contract directly
- **Simpler architecture:** No Rust/Cairo WASM bridge complexity
- **Consistent state:** Single source of truth is the chain

---

## 10. Roadmap

### Phase 1: Core Game (Now)
- [x] Basic board + cap movement
- [x] Attack + ability system
- [x] Tower + win conditions
- [x] Energy economy
- [ ] Commit-reveal for ranked
- [ ] Full cap type roster (24 types)

### Phase 2: Polish & Balance
- [ ] Animations & VFX
- [ ] Sound design
- [ ] Mobile optimization
- [ ] Tutorial / onboarding
- [ ] Set 0 balance passes

### Phase 3: Community Layer
- [ ] $CAPS token launch
- [ ] Governance portal
- [ ] First community vote (balance patch)
- [ ] Set 1 design + vote

### Phase 4: Expansion
- [ ] Custom playlist creator UI
- [ ] Tournament system
- [ ] Spectator mode
- [ ] Set 1 release
- [ ] Ranked seasons

### Phase 5: Meta-Evolution
- [ ] Cross-set synergies
- [ ] Seasonal championships
- [ ] Community-created sets
- [ ] Mobile native app

---

## 11. Open Questions

1. **Should energy carry over?** Currently no — creates urgency but may feel punishing.
2. **Action count limits?** Currently ramps from 1→4. Should it be energy-only?
3. **Surround capture cost?** Currently 2 energy. Balance TBD.
4. **Hidden information variant?** Allow hidden bench caps for bluffing?
5. **Timer enforcement?** On-chain turn timer or honor system?

---

## 12. Glossary

| Term | Definition |
|------|------------|
| **Cap** | Individual game piece/unit |
| **Bench** | Off-board reserve where undeployed caps wait |
| **Set** | Themed collection of cap types, released periodically |
| **Playlist** | Custom game mode with user-defined rules |
| **Tower** | Immobile objective cap — destroy to win |
| **Surround** | Capture mechanic: adjacent to 2+ enemy caps |
| **Energy** | Turn resource spent on actions |
| **Action** | Single deploy/move/attack/ability/retreat |

---

*Document version: 0.1.0*
*Last updated: 2025-08-26*
