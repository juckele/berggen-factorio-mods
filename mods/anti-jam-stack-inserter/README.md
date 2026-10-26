# Anti-jam Stack Inserter

A stack inserter that never jams up waiting for a full hand.

The Space Age stack inserter won't swing until its hand is full, but a hand only holds one kind
of item at one quality, so it can get stuck:

- **Quality items:** A higher quality item from a machine or on a mixed belt can leave it
  stuck waiting for a higher quality item.
- **Spoilable items:** discarding spoilage from a machine can leave it stuck.

An Anti-jam Stack Inserter will swing immediately when picking up items from a chest. When picking up items from a belt it waits about a third of a second before it will swing.

It's purple, in the style of the classic filter inserter, so you can tell them apart at a
glance (other colors are available, see below). It has the same speed, power use, health and
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

### Crafted upgrade

The anti-jam stack inserter is its own item, crafted from a stack inserter, a selector
combinator and a processing unit. It's unlocked with the stack inserter, recycles back into
those three, and can be crafted with quality modules.

## Upgrading from bulk inserters

By default the anti-jam stack inserter is the bulk inserter's next upgrade: an upgrade planner
with no rules set upgrades bulk inserters to anti-jam stack inserters, and downgrades
anti-jam stack inserters to bulk inserters. Turn off **Bulk inserters upgrade to anti-jam
stack inserters** to remove that. Stack inserters themselves still don't upgrade or
downgrade.

## Colors

A startup setting picks the anti-jam stack inserter's color: purple, aqua, magenta or black.
**Automatic** (the default) is purple, or black when the
[Long Stack Inserter](https://mods.factorio.com/mod/long_stack_inserter) mod is
installed, since that inserter is purple too.

**Yellow hand** keeps the stack inserter's yellow hand and only recolors the platform and
arm, the way the long-handed stack inserter looks. It's off by default (the whole inserter
is recolored), and on by default when the Long Stack Inserter mod is installed.

## Long Stack Inserter

With the [Long Stack Inserter](https://mods.factorio.com/mod/long_stack_inserter) mod
installed, you also get a **long-handed anti-jam stack inserter**: the long-handed stack
inserter's reach, without waiting for a full hand. It works like the anti-jam stack inserter
in every item mode, with the long-handed stack inserter in place of the stack inserter: smart
swapping builds it from long-handed stack inserters, the distinct item modes use the
long-handed stack inserter's recipe and research, and the crafted upgrade starts from a
long-handed stack inserter.

More settings appear when it's installed:

- **Long-handed anti-jam stack inserter color:** purple, aqua, magenta or black. Automatic is aqua.
- **Long-handed stack inserter color:** recolors the long-handed stack inserter itself.
  Automatic and purple keep its own colors.
- **Yellow hand** for each of them, on by default so every stack inserter shares the
  long-handed stack inserter's style. Turn it off for a full recolor.

## Compatibility

Works with mods that change the stack inserter: it follows changes to its recipe and research.

## Credits

The anti-jam stack inserter's graphics are adapted from Factorio's stack inserter and the
classic filter inserter, © Wube Software Ltd., and included under the Factorio Terms of
Service. They aren't covered by this mod's MIT license; see `LICENSE-graphics.md`.

The long-handed variants follow the look of snouz's
[Long Stack Inserter](https://mods.factorio.com/mod/long_stack_inserter), and its
recolors are made from that mod's graphics (MIT licensed, themselves adapted from Factorio).
