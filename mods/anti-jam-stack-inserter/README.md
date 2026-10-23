# Anti-jam Stack Inserter

A purple stack inserter that swings without waiting for a full hand.

The Space Age stack inserter waits until its hand is full before it swings. If the source
runs dry it sits there holding a partial stack forever. The anti-jam stack inserter is the
same prototype with `wait_for_full_hand = false`, so it delivers whatever it is holding.

- Same recipe, unlock and stats as the stack inserter. The recipe and unlock are copied
  from the stack inserter in `data-final-fixes`, so changes other mods make to them carry over.
- Recycles to the stack inserter's ingredients.
- Optional quick conversion recipes in both directions (startup setting, on by default).
  They keep the item's quality and don't accept modules, so they can't roll quality upgrades.

Requires Space Age (Factorio 2.1).
