# Anti-jam Stack Inserter

An anti-jam stack inserter that doesn't wait for a full hand, so belt stacking works on lines
carrying mixed quality or spoilable items.

The Space Age stack inserter waits until its hand is full before it swings. A hand holds
one item of one quality, so on a belt of mixed quality it can sit forever holding a partial
hand that the next items can't join, and on a slow line of spoilable items it holds them
while they spoil. The anti-jam stack inserter is the same prototype with
`wait_for_full_hand = false`: it still stacks when items are there, and otherwise swings
with what it has after a brief delay.

Measured on Factorio 2.1.23:

- From a chest it swings immediately with whatever it could take.
- From a belt it swings about 22 ticks (~0.37 s) after its last pickup when no matching
  item arrives, the same with or without inserter capacity research.

Other details:

- Same recipe, unlock and stats as the stack inserter. The recipe and unlock are copied
  from the stack inserter in `data-final-fixes`, so changes other mods make to them carry over.
- Recycles to the stack inserter's ingredients.
- Optional quick conversion recipes in both directions (startup setting, on by default).
  They keep the item's quality and don't accept modules, so they can't roll quality upgrades.

Requires Space Age (Factorio 2.1).

## Graphics

Built from the 1.1 filter inserter and the Space Age stack inserter. Parts the bulk, filter
and stack inserters share come from the filter inserter; parts only the stack inserter has
come from the stack inserter with its yellow trim recoloured to the filter inserter's purple.

- Platform: the filter inserter's (all three share the same silhouette).
- Icon: the filter inserter's legs and turret, the stack inserter's arm and claw head.
- Base arm, hands and remnants: the stack inserter's, yellow trim made purple.
- Shadows and the frozen overlay: vanilla stack inserter.

If another mod has replaced the stack inserter's sprites, those are tinted purple instead.

The conversion recipe icons follow Space Age's nutrient recipes: the input at the top left,
the output slightly larger at the bottom right, in front.
