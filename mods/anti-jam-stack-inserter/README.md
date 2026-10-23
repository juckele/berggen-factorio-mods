# Anti-jam Stack Inserter

A purple stack inserter that doesn't wait for a full hand, so belt stacking works on lines
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

## To do

- Dedicated anti-jam stack inserter sprite and icon (currently a tint of the stack inserter's).
- Once that exists, redo the conversion recipe icons in the style of Space Age's nutrient
  recipes (e.g. nutrients from spoilage). The input icon sits at the top left, just barely
  smaller than the output. The output icon is shrunk from full size and layered in front at
  the bottom right. The current icons put a small copy of the input in the top-left corner of
  the full-size output; with two identical shapes that differ only in colour, they're hard to
  read at inventory size.
