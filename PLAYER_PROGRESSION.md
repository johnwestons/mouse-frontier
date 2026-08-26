# Player Progression

Player growth is governed by `game/player_progression.lua` so Windows and Android use the same capped, save-compatible rules.

## Level curve

The maximum level is 12. Experience needed for the next level is `10 + 6 × (level - 1) + 2 × (level - 1)²`; reaching level 12 takes 1,210 total XP. Older saves keep their current level and XP, while their next-level requirement is recalculated from this curve.

Every level restores the player to full health and raises maximum health by 3. Level bonuses are added to character-trait bonuses in battle.

| Level | Aim | Armor | Move | Ability rank |
| ---: | ---: | ---: | ---: | ---: |
| 1 | +0 | +0 | +0 | 1 |
| 3 | +1 | +0 | +0 | 1 |
| 4 | +1 | +0 | +0 | 2 |
| 5 | +2 | +1 | +0 | 2 |
| 7 | +3 | +1 | +1 | 3 |
| 9 | +4 | +2 | +1 | 3 |
| 10 | +4 | +2 | +1 | 4 |
| 12 | +5 | +2 | +1 | 4 |

The journey HUD shows the current level, experience, special-ability rank, and all three battle bonuses. At level 12 the experience bar becomes a full `MAX` bar.

## Special-ability ranks

The player's character ability improves at levels 4, 7, and 10. NPC allies remain at rank 1, so player advancement remains meaningful without silently scaling every combatant.

| Ability | Rank 1 | Rank 4 |
| --- | --- | --- |
| Heal | Restore 4 HP | Restore 7 HP |
| Rally | +2 aim, +2 move | +3 aim, +3 move |
| Protect | +2 armor | +5 armor |
| Snare | -1 move for 2 rounds | -2 move for 3 rounds |
| Sleep | 2 rounds | 5 rounds |
| Paralyze | 1 round | 2 rounds |
| Area attack | 4 damage | 7 damage |
| Nourish | 2 HP, +1 move | 5 HP, +3 move |
| Repair | 2 HP, +2 armor | 5 HP, +5 armor |
| Haste | +1 aim, +2 move | +2 aim, +5 move |
| Disarm | -2 aim | -5 aim |
| Volley | 5 damage | 8 damage |

Experience comes from battles and completed quests. A deterministic audit checks the curve, level cap, health growth, combat bonuses, and all 12 scaled ability profiles during every desktop and mobile smoke run.
