# Rule and player-flow changes on Matt

## Main changes

1. **Game knowledge is optional.** Every candidate has a Quick intro with its basic gameplay and useful features. Players may use those facts in clues. Jev receives the same underlying candidate information, but not the selected target.
2. **Reading time counts.** Timing starts after Start/Continue opens the level. Reading card descriptions and Quick intros, choosing a target, and writing clues all count toward that level's active time and existing time-based score penalty. Choosing a target does not reset the timer. The title screen, main menu, time outside the focused game window, and Jev's thinking time are not counted.
3. **Main menu preserves the run.** Players can leave for the main menu and continue with the same target, clues, score, and elapsed time. The current clue draft is retained within the session.
4. **Restart run starts over.** It clears the seven-level run's score, target, clues, guesses, draft, and elapsed time, returning to level 1 with the same daily candidate board. It does not generate a new puzzle or reset lifetime streak metadata.

## Rules that remain the same

- Seven levels with increasingly difficult candidate groups and level-specific word/attempt limits.
- Players give clues; Jev guesses. The selected target stays hidden from Jev.
- Title words and list-position shortcuts are not allowed.
- Fewer clues, fewer words, and less active time earn more points. The score formula and its 150-second maximum time penalty are unchanged; a missed level scores zero.
- Daily boards remain date-based. The curated fallback contains two alternating packs; when current external data are available, the regular game composes a seeded daily board. Restarting keeps today's board.

## Presentation changes, not scoring changes

The branch also adds the illustrated title screen, beginner-friendly cards and game artwork, Total score beneath Jev, navigation buttons, fullscreen settings, background music, and button/progress feedback sounds. Music and sound-effects preferences are independently adjustable and saved.

## Technical verification

The existing generator could reject valid daily pools when its greedy partial-group search missed the required similarity floor. A bounded seeded full-group fallback now preserves solvability, distinguishability, and difficulty progression; tests check both daily variants and determinism. This fixes generation reliability without changing the intended rules.
