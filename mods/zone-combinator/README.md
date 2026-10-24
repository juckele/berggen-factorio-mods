# Space Exploration Zone Combinator
Combinator that outputs detailed information about the zone in which it is placed. Inspired by Baisius's discord [suggestion](https://discord.com/channels/419526714721566720/1161305206177402921).

## Features
1. Introduces 4 new virtual signals: 'Day Length', 'Solar', 'Threat', and 'Robot Interference'.
1. Introduces a special 'zone combinator' that's effectively a constant combinator that is automatically built with a number signals describing the zone.
    1. X and Y tile position of the combinator when placed.
    1. Zone id, set on a channel corresponding to the zone type.
    1. Radius, set on the 'Radius' signal.
    1. Day length, set on the 'Day Length' signal and measured in ticks.
    1. Solar, measures solar efficiency with `value 100 = 100%`.
    1. Threat, as presented by the Universe Explorer, `value 100 = 100%`.
    1. Water, a water signal of 1 is set on planets and moons that aren't waterless. Zones that can't have water (waterless hazard, or any zone that isn't a planet or moon) have no water signal.
    1. Biter Meteors, if present a meteor signal of 1 is set.
    1. Plagued, if present a plague rocket signal of 1 is set.
    1. Life Support, if needed a life support canister signal of 1 is set.
    1. Core Fragment Type, if present a core fragment of the appropriate type will be used as a signal with value 1.
    1. Robot Interference, either wind or radiation is set on a new virtual signal and measured as presened by the Universe Explorer with a 100x scaling factor (1.00 = 100)
    1. Resources, frequency, size, and richness are multiplied together, `value 10,000 = 100%`. Water is reported as a flag (above), not as a resource.

## Limitations
1. Many of the units the combinators put out are capricious. Day length is in ticks, threat and solar are in percent (100 = 100%), resources(ore/oil) are in 1/100 of a percent (10k = 100% on mapgen settings), radius are in game units, robot interference are in in game units x100, flags like water, life support, plagued, and core type are flags with a value of 1 if present. 
1. If a plague rocket converts the primary resource of a zone from vitamelange to coal, the zone combinator primary resource output will not update until it is rebuilt.

## Combinator Mask
1. The source for this mod contains a mask for constant combinator tint for its entity and item - it should make adding different colored combinators easier in other mods.

## Credits
1. [test447](https://mods.factorio.com/user/test447) - code, combinator mask
1. [berggen](https://mods.factorio.com/user/berggen) - code
1. [Twemoji 15.0.1](https://github.com/jdecked/twemoji), © Twitter, Inc. and other contributors - virtual signal emoji, under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/); see `LICENSE-emoji.md`
1. The combinator masks and thumbnail are adapted from Factorio's constant combinator, © Wube Software Ltd., and included under the Factorio Terms of Service. They aren't covered by this mod's MIT license; see `LICENSE-graphics.md`.
