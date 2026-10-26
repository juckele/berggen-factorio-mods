# Anti-jam Stack Inserter

A stack inserter that never jams up waiting for a full hand.

The Space Age stack inserter won't swing until its hand is full, but a hand only holds one kind
of item at one quality, so it can get stuck:

- **Quality items:** A higher quality item from a machine or on a mixed belt can leave it
  stuck waiting for a higher quality item.
- **Spoilable items:** discarding spoilage from a machine can leave it stuck.

An Anti-jam Stack Inserter will swing immediately when picking up items from a chest. When picking up items from a belt it waits about a third of a second before it will swing.

It's purple, in the style of the classic filter inserter, so you can tell them apart at a
glance (other colours are available, see below). It has the same speed, power use, health and
hand size as the stack inserter, and inserter capacity research applies the same way.

## Getting anti-jam stack inserters

A startup setting, **Item mode**, chooses how they're obtained.

### Smart swapping (default)

There's nothing extra to craft or research: anti-jam stack inserters are built from your
stack inserters, and mining one gives you a stack inserter back, keeping its quality.

- **Upgrade planner:** add a rule from stack inserter to anti-jam stack inserter (or the
  other way) and drag it over your inserters. Construction robots swap them for free. Set
  the rule's quality to match the inserters you're upgrading.
- **Blueprints and ghosts:** anti-jam stack inserters in a blueprint are built by
  construction robots from stack inserters in your logistic network.
- **Pipette (Q):** pipette an anti-jam stack inserter or its ghost and you can place real
  ones straight from the stack inserters in your inventory.
- **Quickbar:** you can put the anti-jam stack inserter on your quickbar. If your interface
  settings give you a ghost when you pick an item you don't have, picking it uses the stack
  inserters in your inventory instead.
- Placing a stack inserter from your inventory still places a regular stack inserter.

Your inventory, chests and logistic network only ever hold stack inserters, so there's
nothing separate to stock or request. Cheat mode can create actual Anti-jam Stack Inserters
but that's up to the user to deal with.

If you switch an existing save to smart swapping, any anti-jam stack inserter items are
turned back into stack inserters when the save loads.

### Distinct item

The anti-jam stack inserter is its own item. It's crafted with the same recipe as the stack
inserter, unlocked by the same research, and recycles into the same ingredients.

### Distinct item with quick swap

As distinct item, plus two quick recipes that turn a stack inserter into an anti-jam stack
inserter and back. They keep the inserter's quality and don't take quality modules, so can't
be used to cheese quality.

## Colours

A startup setting picks the anti-jam stack inserter's colour: purple, aqua, magenta or black.
**Automatic** (the default) is purple, or black when the
[Long-handed stack inserter](https://mods.factorio.com/mod/long_stack_inserter) mod is
installed, since that inserter is purple too.

## Long-handed stack inserter

With the [Long-handed stack inserter](https://mods.factorio.com/mod/long_stack_inserter) mod
installed, you also get a **long-handed anti-jam stack inserter**: the long-handed stack
inserter's reach, without waiting for a full hand. It works like the anti-jam stack inserter
in every item mode, with the long-handed stack inserter in place of the stack inserter: smart
swapping builds it from long-handed stack inserters, and the distinct item modes use the
long-handed stack inserter's recipe and research.

Two more colour settings appear when it's installed:

- **Long-handed anti-jam stack inserter colour:** purple, aqua, magenta or black. Automatic is aqua.
- **Long-handed stack inserter colour:** recolours the long-handed stack inserter itself (its
  hand stays yellow). Automatic and purple keep its own look.

## Compatibility

Works with mods that change the stack inserter: it follows changes to its recipe and research.

## Credits

The anti-jam stack inserter's graphics are adapted from Factorio's stack inserter and the
classic filter inserter, © Wube Software Ltd., and included under the Factorio Terms of
Service. They aren't covered by this mod's MIT license; see `LICENSE-graphics.md`.

The long-handed variants follow the look of snouz's
[Long-handed stack inserter](https://mods.factorio.com/mod/long_stack_inserter); their graphics
are made from the same Factorio sources as above.
