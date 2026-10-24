# Anti-jam Stack Inserter

A stack inserter that never sits waiting for a full hand.

The Space Age stack inserter won't swing until its hand is full. A hand only holds one kind
of item at one quality, so it can get stuck:

- **Mixed quality belts:** it grabs a few normal items, then the belt brings rare ones that
  can't join them, and it waits forever.
- **Spoilable items:** on a slow line it holds what it has picked up until it spoils.
- **Sources that run dry:** a nearly empty chest or a trickling belt leaves it holding a
  partial hand.

The anti-jam stack inserter still stacks up to its full hand size when items are there. When
nothing more it can pick up arrives, it swings with what it has:

- From a chest it swings straight away with whatever it could take.
- From a belt it waits about a third of a second for more matching items, then swings.

It's purple, in the style of the classic filter inserter, so you can tell them apart at a
glance. It has the same speed, power use, health and hand size as the stack inserter, and
inserter capacity research applies the same way.

Requires Space Age.

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
  ones straight from the stack inserters in your inventory. If you don't have any, you get an
  anti-jam stack inserter ghost to place instead.
- **Quickbar:** you can put the anti-jam stack inserter on your quickbar. If your interface
  settings give you a ghost when you pick an item you don't have, picking it uses the stack
  inserters in your inventory instead.
- Placing a stack inserter from your inventory still places a regular stack inserter.

Your inventory, chests and logistic network only ever hold stack inserters, so there's
nothing separate to stock or request.

If you switch an existing save to smart swapping, any anti-jam stack inserter items in it
are turned back into stack inserters when the save loads.

### Distinct item

The anti-jam stack inserter is its own item. It's crafted with the same recipe as the stack
inserter, unlocked by the same research, and recycles into the same ingredients.

### Distinct item with quick swap

As distinct item, plus two quick recipes that turn a stack inserter into an anti-jam stack
inserter and back. They keep the inserter's quality and don't take modules, so they can't
be used to roll quality.

## Compatibility

Works with mods that change the stack inserter: it follows changes to its recipe and
research, and if a mod reskins the stack inserter, the anti-jam one gets that look in purple.
