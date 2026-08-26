# Progression balance baseline

Verified on August 25, 2026.

The former travel curve consumed 325 food, 425 water, and 295 coal over the 49 legs from stop 1 to stop 50 before passenger, trait, maintenance, or engine modifiers. With 30-unit stores, its late-game costs made repeated scavenging mandatory and obscured the value of train upgrades.

The `milestone-v1` curve consumes 145 food, 175 water, and 175 coal over the same baseline route. Individual unmodified legs are capped at 5 food, 7 water, and 7 coal. Passenger load adds at most three food and water; a sleeper car halves that load before the cap. Character traits, engine upgrades, terrain, and maintenance remain meaningful modifiers.

The deterministic audit enforces:

- 49 modeled travel legs.
- Baseline totals of 145 food, 175 water, and 175 coal.
- Maximum baseline leg costs of 5 food, 7 water, and 7 coal.
- Compatibility with the existing 30-unit resource stores.
- Exact travel affordability in desktop and mobile controls, including visible costs and shortage feedback.
