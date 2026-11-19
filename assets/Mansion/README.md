# Hollowmere House: Victorian mansion models

Twenty-four pieces for an abandoned Victorian mansion: dark carved mahogany and walnut, faded velvet,
tarnished gilt and brass, foxed and cracked mirrors, and a layer of dust on everything. Low poly,
with baked colour and normal maps embedded in each FBX.

| Piece | What it is | Size (studs, W x D x H) |
|---|---|---|
| FourPosterBed | Carved mahogany four-poster: turned posts and finials, arched panelled headboard with a carved shell, canopy and valance, rotted red drapes tied back to the posts, a dusty coverlet | 5.3 x 6.9 x 7.0 |
| Wardrobe | Tall carved wardrobe: cornice and crest, the left door standing ajar on a faded white dress, the right door with a foxed, cracked oval mirror; both doors open | 4.3 x 3.0 x 7.0 |
| WingbackArmchair | Wingback armchair in faded red velvet: deep-buttoned back, scrolled arms, cabriole legs | 2.8 x 2.7 x 4.0 |
| SheetedSofa | A camelback sofa under a grey dust sheet, only its carved feet showing | 6.0 x 2.7 x 3.1 |
| DiningTable | Long dining table on six turned legs, carved scalloped aprons, laid years ago and left: runner, plates, tarnished cutlery, the soup tureen, crystal goblets (one knocked over) | 6.9 x 3.3 x 3.1 |
| DiningChair | Balloon-back dining chair: carved hoop back, red velvet seat, turned front legs | 1.3 x 1.4 x 3.5 |
| UprightPiano | Walnut upright piano: candles in its brass sconces, yellowed keys (a few sunk, one missing), a nocturne on the music desk, brass pedals; its stool | 4.6 x 3.7 x 4.0 |
| GrandfatherClock | Long-case clock: glazed trunk showing the pendulum and weights, turned hood columns, broken-arch pediment, finials; stopped at 3:14 | 1.9 x 1.1 x 7.3 |
| WritingDesk | Bureau with its fall-front down: pigeonholes full of letters, an unfinished letter and spectacles on the blotter, inkwell and quill, an oil lamp and books on top | 3.1 x 2.6 x 4.5 |
| Bookcase | Tall glazed bookcase: four shelves of old books behind the glass doors, a panelled cupboard below | 4.2 x 1.6 x 7.0 |
| RockingChair | Spindle-back rocking chair on bow rockers, a crocheted shawl left over the back | 2.0 x 2.9 x 3.4 |
| VanityDresser | Dressing table with a cracked swing mirror: brushes, perfume bottles, a powder jar, pearls, a photograph lying face down | 3.3 x 1.6 x 4.8 |
| Candelabra | Five-light brass candelabra, candles burnt down unevenly and dripping wax, still lit | 1.0 x 1.0 x 1.9 |
| Chandelier | Brass chandelier: ceiling rose and chain, eight scrolled arms with candles (two snapped off), crystal drops and swags | 2.9 x 2.8 x 4.0 |
| PortraitPainting | Oil portrait of the lady of the house in an ornate gilt frame, hanging crooked, her eyes scratched out | 2.4 x 0.2 x 2.9 |
| ManorPainting | The house itself at night in oils: towers and gables on the hill, dead trees, one window lit | 3.1 x 0.2 x 2.5 |
| StandingMirror | Cheval mirror: foxed, cracked oval glass between turned uprights on splayed feet | 2.4 x 1.5 x 5.0 |
| PersianRug | Worn Persian rug (2.4 x 1.6 m): medallion and borders, a stain, fringes, one corner kicked up | 4.8 x 7.7 x 0.5 |
| Gramophone | Horn gramophone: walnut case and crank, a shellac record, the tone arm, a big brass flower horn | 1.8 x 2.0 x 2.8 |
| DeadFlowerVase | Blue-and-white china vase of dead roses drooping over the rim, petals fallen round it | 1.0 x 1.2 x 1.5 |
| LibraryBookshelf | Tall open library bookshelf: fluted pilasters, carved crest, six shelves packed with old books (flat stacks, gaps, one leaning), an hourglass, a globe, a candle stub, two books fallen on the floor; the rolling ladder on its brass rail | 5.5 x 3.0 x 8.0 |
| CarvedArmchair | Tall carved oak armchair, almost a throne: finials, a pointed crest with rosettes, buttoned green velvet edged with brass nails, scrolled arms | 2.0 x 1.9 x 4.7 |
| FamilyPortrait | The family in oils: father, mother, the boy, the little girl in white with her doll. His face is burnt out of the canvas, her eyes painted over black. Gilt frame, hanging crooked | 3.5 x 0.2 x 2.6 |
| VanitasPainting | Vanitas still life in a black ebony frame: a skull on a book by a guttered candle, an hourglass run out, a wilted flower | 1.8 x 0.2 x 2.1 |

The front of every piece faces **+Z** in Studio. The previews (`previews/`) show how each piece
looks after `SetupMansion`.

## Bringing them in

1. **Import:** File > Import 3D, pick one FBX (or `Mansion_All.fbx` for everything side by side).
   If the sizes look 3x too small or big, set the importer's Scale Unit to **Stud**.
2. **Set up:** run `tools/SetupMansion.lua` in the Command Bar, with the imported models selected
   (or nothing selected, to do every mansion piece in the Workspace). It:
   - lights every candle flame: warm Neon plus a PointLight that casts shadows;
   - turns the clock, bookcase and oil-lamp glass see-through, and makes the chandelier's crystal
     drops sparkle;
   - gathers `Mansion_All.fbx` into one Model per piece;
   - puts the wardrobe doors' pivots on their hinges.
3. **Flicker:** put `src/StarterPlayerScripts/CandleFlicker.client.lua` in StarterPlayerScripts
   and every candle flickers like a real flame. The light's `BaseBrightness` attribute sets what
   it flickers around. A light you switch off (`Enabled = false`) stays off.

All candles are lit: the candelabra, the chandelier, the piano's sconces and the oil lamp on the
writing desk. To have them unlit (or blow them out in a scare), delete or hide the `Flame`
parts and turn their `CandleLight` off.

## Loose parts

- **UprightPiano:** its stool is a separate part (`Stool`), so you can move it.
- **LibraryBookshelf:** its rolling ladder is a separate part (`Ladder`): slide it along the brass
  rail, or take it away.
- **Wardrobe:** each door is its own part with its pivot on the hinge (after SetupMansion). The
  left door is modelled standing ajar, with a faded white dress hanging inside. It's a good
  hiding spot.

```lua
local w = workspace.Wardrobe
-- close the left door (it's modelled 28 degrees open)
w.DoorLeft:PivotTo(w.DoorLeft:GetPivot() * CFrame.Angles(0, math.rad(28), 0))
-- swing the right door open
w.DoorRight:PivotTo(w.DoorRight:GetPivot() * CFrame.Angles(0, math.rad(100), 0))
```

## Placing things

- **Paintings** (PortraitPainting, ManorPainting, FamilyPortrait, VanitasPainting): the back sits on the wall. They hang slightly
  crooked on purpose.
- **Chandelier:** hang it by the ceiling rose. It's 1.25 m (3.75 studs) from the ceiling to the
  bottom drop.
- **PersianRug:** lies flat on the floor, with one corner kicked up.
- **Candelabra** and **DeadFlowerVase:** made to stand on the dining table, the piano or the
  dresser.
