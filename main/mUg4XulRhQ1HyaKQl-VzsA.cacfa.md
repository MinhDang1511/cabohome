# CABO Prototype — Design & Implementation Reference

This document captures every game-rule and architecture decision locked in so far for the CABO digital prototype, so anyone (or any tool) picking up the project — including Claude Code working directly in the engine project — has the full context without needing the original design conversation.

## 1. Scope

- 2–6 players (humans + bots), host-configured. **This supersedes the earlier "exactly 2 players" scope** — see Section 14 for seats, bots and the setup screen. Code that assumed a single opponent (`performBlindSwap`, `BotPlayer.getOpponentIndex`, single `botPlayerIndex`) must be generalized.
- Priority order for the prototype (deadline ~1.5 weeks): rules/abilities/penalties and N-player support first, real online play last (Section 15).
- Built on a proprietary in-house 2D engine (TypeScript, PixiJS-based, Unity/Cocos-Creator-style editor). See Section 10 for engine conventions.
- All gameplay logic lives in script components; Inspector wiring (button Click Handlers, node reference fields, prefab setup) is done manually in the editor GUI and is not captured in script form.

## 2. Turn Structure

`TurnManager` drives a phase state machine:

- **WaitingForDrawChoice** — the active player may draw from the pile, take the discard, or call CABO (CABO can be called alongside drawing, not instead of it — see Section 4).
- **WaitingForReplaceChoice** — a card has been drawn/taken; the player selects 0, 1, or 2+ of their own slots, then confirms via the discard pile.
  - 0 selected → discard the drawn card without replacing (always legal, no conditions).
  - 1 selected → replace that slot with the drawn card; the old card goes to the discard pile.
  - 2+ selected → attempt the same-value swap (Section 3).
- **WaitingForAbilityTarget** — active only after discarding a rank 7/8/9 card drawn from the pile (Section 5); waiting for the player to click the required target slot(s).
- **RoundOver** — set once CABO's final lap completes or the low-deck block triggers (Section 4). All hands are revealed and the result is displayed.

## 3. Same-Value Swap Rule (Section 9 of the original rules)

When 2 or more of the current player's own slots are selected to confirm a draw:

- The selected slots must match **each other** — the drawn card's value is irrelevant to this check. This can involve 2, 3, or 4 matching slots.
- **Correct guess:** all but one of the matched cards are discarded outright (their slots emptied, and they stay empty for the rest of the round); the drawn card takes the place of the first matched slot. Turn ends normally. A hand therefore never drops below 1 card.
- **Wrong guess:** the drawn card is discarded, the selected cards are **revealed to everyone** for a few seconds (`peekAbilityDuration`) and stay in their slots, and **the turn ends**. The wrong guess is **announced to everyone**. (This supersedes the old "pick again" behavior, the earlier "keep the cards and add the drawn card as an extra slot, 6-slot cap" idea, and the old "no penalty" TODO. Hands never grow, so there is no hand cap and no extra-slot UI.)
- Implemented in `attemptSameValueSwap()`'s rejection branch in `TurnManager.ts`. `confirmSelection()` now returns `false` only when the swap is invalid (the card wasn't drawn from the pile); `BotPlayer`'s fallback for that case stays.
- Discarding the drawn card without replacing (0 slots selected) has **no conditions at all** — it does not require having any duplicate cards. This was corrected twice during design; make sure any future change doesn't reintroduce a gate here.

## 4. Calling CABO

- Calling CABO does **not** end the turn by itself. The caller calls CABO and then still draws/resolves normally that same turn.
- Every other player then gets exactly one final turn.
- The round ends once play loops back around to the caller.
- **Blocked call (changed 2026-10-30):** if the draw pile has fewer cards remaining than there are *active* players at the moment of the call attempt, the call is refused with the message "Can't call CABO: the card pile is going empty." and the round simply continues (no CABO, no round end). The round then ends only when the pile is drawn out completely (see Section 13, +5 to every tied-lowest hand).
- **Draw pile empties:** when the last card is drawn, that player finishes their turn normally (replace/discard, plus any ability that doesn't need the pile), then the round ends. Every player tied for lowest hand score gets +5. If CABO was called, the CABO resolution takes priority over the +5. Rank 5 cannot be used once the pile is empty.
- **Caller resolution and reward points:** see Section 13.
- **Ties for equal lowest hand scores:** all tied players count as lowest (they share the lowest-score payouts); no separate tie-break rule.

## 5. Card Visibility Rules

- `Card.faceUp` defaults to `false` — hidden by default.
- At the start of a round, only the **local player's** first 2 cards are revealed, for a short configurable duration, then auto-hide. This is `PlayerHand.isLocalPlayer` + `revealStartingPeek()` — designed so that in future online play, each client only ever sees its own opening peek.
- The discard pile is **always** revealed — pushing a value there always calls `card.reveal()`.
- The shared "drawn card" display is revealed while pending, with one exception: **when it's the bot's turn, a card drawn from the pile stays hidden ("?")** so the human can't see what the bot drew. A card *taken from the discard pile* stays revealed even during the bot's turn, since the discard pile was already public before it was taken — there's no new information to hide.
- Ability peeks (ranks 7/8/9) reveal on the single shared screen regardless of who triggered them — there's no per-player view separation yet. This is a known, accepted limitation of the current shared-screen prototype, not a bug.

## 6. Card Abilities

Ability trigger rule (applies to all of the below): the ability only fires when the ability-rank card was **drawn from the draw pile** (not taken from discard) **and then discarded without replacing** (0 slots selected at confirm). Replacing a slot with the ability card, or involving it in a same-value swap, never triggers its ability.

**Using an ability is always optional.** After discarding an ability card the player may press a "Skip ability" button instead of picking targets; the turn then ends. (Needs a lock-gated human-click wrapper like the other buttons, wired in the editor. Bots may use or skip, with a skip chance tied to `mistakeChance`.) Skipping still shows an announcement ("Player N chose not to use the Rank X ability"). If an ability can't do anything (e.g. rank 6 against a target with fewer than two cards), the player can only skip and the turn ends.

**Targeting (multiplayer):** the caster picks the target player by clicking one of that player's slots (`CardSlot.playerIndex` identifies the owner). No ability can target the caster themselves (ranks 5, 6, 8; rank 9 uses one own slot + one other player's slot). Any other active player is a valid target, including one who just called CABO. Idle seats are never valid targets.

- **Rank 7 — Peek Own:** reveal one of your own slots for a few seconds. Built.
- **Rank 8 — Peek Opponent:** reveal one slot of a chosen other player for a few seconds. Built for 2 players; needs target-player choice for N players.
- **Rank 9 — Blind Swap (self/other):** swap one of your own cards with one of a chosen other player's, blind. A genuine physical swap — the two card nodes animate to each other's slots (`CardSlot.setCardNode()`). Built for 2 players; needs target-player choice for N players.
- **Rank 5 — Forced Draw:** the caster picks a target player. The target draws the top card of the draw pile, **sees it**, and must replace one of their own slots with it (they **cannot decline**). The replaced card goes face-up onto the discard pile. Not usable if the draw pile is empty. **Implemented 2026-10-09 (uncompiled):** a human target clicks their own slot; a bot target picks on its own; the drawn card is shown to a human target on the shared screen and hidden for a bot target. (Supersedes the earlier "swap two opponent slots" and "swap two own cards" ideas for rank 5.)
- **Rank 6 — Opponent Slot Swap:** the caster picks one other player and swaps two of that player's slots with each other, blind; the caster's hand is untouched. If the target has fewer than two cards, the ability can't be used (skip only). **Implemented 2026-10-09 (uncompiled):** the caster clicks two different slots of the same other player; clicking the first slot again cancels the pick.
- **Ranks 2, 3, 4, 10, 11, 12:** no ability (plain point cards) for the prototype.
- Because ability cards reveal on the shared screen and rank 5 shows a card to the target, per-player visibility is deferred (Section 5, Section 15).

## 7. Bot Opponent (`BotPlayer.ts`)

- **Memory instead of perfect information (2026-10-22, uncompiled):** the bot keeps a memory of `seat:slot -> card id` and decides from estimates (a card it hasn't seen counts as the deck average, 6.75). It learns only what a player could: its own opening peek (slots 0 and 1, read when the round is dealt), its own rank 7/8 peeks, cards it drew and placed, cards taken from the discard pile and placed (public), cards shown after a wrong same-value guess (public), and slot swaps (rank 6/9 move the remembered cards with the slots). It forgets each remembered card with `forgetChance` at the start of its turn. `TurnManager` feeds this through `addGameObserver()` / `emitGame()` (events `round`, `place`, `gone`, `swap`, `peek`, `shown`). Same-value swaps use only remembered matches. The bot still reads real data for occupancy (a slot being empty is public) and for the card it is holding.
- **Deliberately "easy" despite that knowledge:** a tunable `mistakeChance` (0–1) makes it skip objectively-good plays some fraction of the time (ignoring a good discard, not replacing its worst card, not attempting a same-value swap it could see, picking a random slot instead of its worst/the opponent's best during a rank 9 swap, not calling CABO even when low).
- **~1 second pause before each action** for watchability, implemented as a simple wait-timer in `update(dt)`, mirroring the pattern already used for `Card.revealTimer`.
- **No event/notification system exists in this engine** — the bot polls `TurnManager.getCurrentPlayerIndex()` / `getPhase()` every frame to detect when it's its turn.
- The bot drives the game exclusively through `TurnManager`'s existing methods (`drawFromPile()`, `takeFromDiscard()`, `callCabo()`, `toggleSlotSelection()`, `confirmSelection()`), the same state machine a human's clicks trigger — it does not go through the human-click-only wrapper methods (`onDrawPileClicked()`, `onCaboButtonClicked()`, `onDiscardPileClicked()`), since those are now gated by the input lock (Section 8) and would block the bot during its own turn.
- **Multiplayer:** with 2–6 players, bots are host-configured (Section 14). The single-opponent assumptions in this file's current code (`opponentPlayerNode`, `getOpponentIndex()`) need to become per-target logic, and bots need to use/skip every ability (Section 6).
- **Known accepted gap (not yet fixed):** because the bot reads real card values from frame one, it can spot and act on a same-value match among its own cards at the very start of a round — before even a human's own 2-card opening peek would reveal that to them. Planned fix (not yet built): give the bot its own tracked "memory" of only what it has legitimately seen (its own starting hand, plus anything revealed to it afterward via peeks/abilities) instead of reading the opponent's hand freely at any time, and lower `mistakeChance` once that's in place.

## 8. Input Locking During Bot Turns

- `TurnManager.botPlayerIndex` (default `-1` = no bot) marks which player index is bot-controlled.
- `isInputLocked()` / `isBotTurn()` returns true whenever it's that player's turn.
- Human-click entry points — `onDrawPileClicked()`, `onCaboButtonClicked()`, `onDiscardPileClicked()`, and `CardSlot`'s click path via `canTargetSlot()` — all check this and no-op during a bot turn, so a stray click can't interfere with or steal the bot's action.
- The bot itself bypasses all of these wrappers, calling the underlying methods (`drawFromPile()`, `takeFromDiscard()`, `callCabo()`, `confirmSelection()`, `toggleSlotSelection()`) directly — none of those raw methods are lock-gated, only the click wrappers are. This split is deliberate: locking the raw methods would also lock the bot out of its own turn.
- **Editor wiring requirement:** the draw pile button's Click Handler must point at `TurnManager.onDrawPileClicked`, and the CABO button's at `TurnManager.onCaboButtonClicked` — not at `drawFromPile`/`callCabo` directly. The discard pile's Click Handler stays on `onDiscardPileClicked` (unchanged target, now also gated).

## 9. Recoverable Wrong Guesses

- `confirmSelection()` and `attemptSameValueSwap()` return a `boolean`: `true` if the turn actually advanced, `false` if the attempt was rejected (wrong same-value guess) and the same player needs to choose again.
- `BotPlayer` checks this return value; on `false` it falls back to the one always-legal move (confirm with nothing selected, i.e. discard the drawn card) so it can never get permanently stuck retrying a failed guess.
- This was a real bug, not just a design nicety: before this fix, a wrong guess during the bot's turn froze the game, because the bot's post-confirm bookkeeping misread "phase didn't move to ability-target" as "the turn must already be over."

## 10. On-Screen UI Feedback

Two Label-driven fields on `TurnManager`, added because the game previously communicated everything through `console.log` only, which falls apart once a player can't see a dev console (or is just watching a bot play):

- **`statusNode`** — always shows whose turn it is and the current actionable instruction. During a bot turn it shows a generic "Player N's turn - thinking..." instead of the instruction, since that instruction isn't actionable by the human anyway.
- **`announcementNode`** — a persistent "most recent notable event" line, specifically for ability use (both when one starts and when it resolves) and CABO calls. It's deliberately separate from `statusNode` so these don't get instantly overwritten the moment the acting player's turn phase changes.
- `resultNode` (pre-existing) remains the dedicated end-of-round reveal display (all hands revealed, totals, winner) — separate from the two above.
- Known limitation: each is a single Label, so only the latest message shows — there is no scrollable history. A real log feed would need a different UI approach, not yet built.

## 11. Current File Map

- `Card.ts` — reveal/hide/timed-peek primitives, movement (`slideTo` with arrival callback, `snapTo` clearing in-progress slide state).
- `CardSlot.ts` — click routes through `TurnManager.canTargetSlot()` + `toggleSlotSelection()`; `setCardNode()` lets a slot's physical card be reassigned (used by rank 9's real swap).
- `PlayerHand.ts` — `isLocalPlayer` / `openingPeekSeconds` (7 s) gate the opening peek; `revealAll()` for end-of-round.
- `DiscardPile.ts` — always-public pile; `push()` can animate in from a given origin; `take()` hides its own display.
- `TurnManager.ts` — the central state machine; owns all of Sections 2–10 above.
- `BotPlayer.ts` — the bot opponent described in Section 7.
- `Deck.ts`, `WorldPos.ts` — existing support files, not modified or reproduced in this reference (assumed: `Deck` has `buildDeck()`/`shuffle()`/`draw()`/`remainingCount()`; `WorldPos` has `getWorldPosition(node)`/`worldToLocal(parent, x, y)`).

## 12. Engine Conventions & Gotchas

For anyone (or any tool) editing this codebase:

- `pcclass` is the class decorator; components extend `Component` (which exposes `.node` publicly); fields use `@property` (bare primitives), `@property(Node)` (single node reference), or `@property([Node])` (array of node references). **Arrays of a custom component type, e.g. `@property([CardSlot])`, do not reliably compile in this engine** — route through `Node` arrays and `.getComponent()` instead.
- `Node` positions (`.position`, `.setPosition(x, y, z)`) are always local to the immediate parent. Use `WorldPos.ts`'s `getWorldPosition(node)` / `worldToLocal(parent, worldX, worldY)` for any cross-hierarchy position math.
- `Label` exposes a plain `.text` string property; supports multi-line via `\n`.
- `UIButton` click behavior is wired **only** through the Inspector's Click Handlers list — there is no code-based click API. Any method a button should call must be `public`.
- Component lifecycle: `onLoad()` runs for every component before any component's `start()` runs; `start()` runs once; `update(dt)` runs every frame with `dt` as delta seconds.
- Compile errors only surface in the editor's separate build/compile log panel after saving — there are no live red squiggles or Play-window console errors for this setup.
- A script attached to a prefab instance in-scene may need saving on the prefab asset itself (Assets tab), not just the scene, to take effect.
- Duplicating a node/component in the editor does **not** remap reference fields or redistribute plain value fields (position, slotIndex, etc.) — every field must be manually re-verified after duplicating.
- Inspector-driven state (Click Handlers, prefab field wiring, node references) is serialized into scene/prefab data files, not readable TypeScript — treat that wiring as editor-GUI-only work, not something to script or hand-edit via raw file access.

## 13. Match & Scoring

Two separate scores: the **hand score** (sum of card points, lower is better, decides who is "lowest" in a round) and the **reward score** (match total, higher is better, can go negative).

- A match is **10 rounds**; the player with the highest reward score after round 10 wins. Single-round restart is still available — the room host can start a new game.
- **Caller strictly lowest** (no other player ties them): caller gets **+20**.
- **Caller ties or loses:** caller gets **-20**; that 20 is split among the other active players. Each non-caller player with the lowest hand score (including non-callers tied with the caller) gets a **double** share, everyone else a single share (e.g. 4 players with one lowest non-caller: shares 10/5/5; with 2 players the one opponent gets all 20). Round to whole numbers.
- **No CABO resolution** (the draw pile empties — Section 4; a refused CABO call no longer ends the round): every player tied for lowest hand score gets **+5**; nobody else scores.
- A CABO resolution always overrides the +5.
- Rounds can only end through a CABO lap or the draw pile emptying — there is no separate "normal win" reward.
- **Built** in `TurnManager` (`computeRewards`, `startNextRound`, `onNextRoundClicked`): reward values are inspector properties (`caboWinReward`, `caboLossPenalty`, `lowestHandReward`, `totalRounds`), each player's reward score shows on a label in front of their own hand (`PlayerHand.scoreLabelNode`, updated by `TurnManager.updateScoreboard`) while `scoreboardNode` only shows "Round X/N", and the host's "Next round" button calls `onNextRoundClicked()`. After round `totalRounds` the match result is shown and the same button starts a new match with scores reset. Each new round reshuffles (`Deck.reset`), empties the discard pile, redeals every slot's original card, and rotates the starting seat to the next active seat (a default, not a locked rule). Not host-restricted yet — that needs the setup screen / online.

## 14. Seats, Bots & Setup

- The table has 6 seats. The **host** sets the number of humans and the number of bots on a **simple setup screen** (scripts provide the API; the UI is built in the editor). Total active players must be ≥ 2. Bots are optional and may be zero. Setup is **fixed for the whole match**.
- Seats not used stay in the scene but are **idle**: skipped in turn order and the CABO lap, never valid targets, excluded from the blocked-call card-count check and from all reward payouts, and their hands/slots hidden or inert.
- Each active bot seat needs its own bot controller; `TurnManager.botPlayerIndex` (single int) must become a set of bot seats.
- Bots must support every rule: all abilities (use or skip), same-value swaps, CABO, and the hand-size cap.

## 15. Online Play (Lowest Priority)

- The target is real online play (separate clients, a host/room, per-player views), but it is explicitly **last** in priority. It's unknown whether the engine has networking; someone with engine access must check. If not, online is out of scope for the prototype.
- **Per-viewer perspective (online only):** every player sees the table from the bottom seat — their own card slots at the bottom of their own screen, with the other players arranged around them (as if each viewer were "Player 1"). Rules and logic still use fixed global seat numbers (host seat 0, then joiners, then bots); only the screen position is relative: `screenPosition = (seat - mySeat + playerCount) mod playerCount`. This needs a layout script that places each seat's node per viewer, position sets for 2–6 players, "Player N" labels, and `isLocalPlayer` set from the client's own seat. It needs multiple clients, so it is **not built**: the single-screen prototype keeps a **fixed view with seat 0 at the bottom**, and does not rotate per turn.
- Until then keep rules logic separate from display where practical (authoritative-state friendly), and keep `isLocalPlayer`-style gating for hidden information. Peeks currently show on the shared screen, which is accepted for the local prototype.

## 16. Explicitly Deferred / Not Yet Started

- Section 14 setup screen: code written 2026-10-09 (uncompiled), editor UI pending. Decided with the user: the host sets each seat to Off / Human / Bot with per-seat buttons (seats may have gaps, so "humans first, bots after" is no longer required); the whole game (`GameRoot`) is hidden and nothing is dealt until Start; after a match the game returns to the setup screen. (Ranks 5 and 6 are built.) (Optional-ability skip is built: `TurnManager.skipAbility()` / `onSkipAbilityClicked()`, bot skips with chance `mistakeChance * skipChanceFactor` and whenever it has no valid target.) (N-player seats/idle seats, the wrong-guess penalty, pile-empty round end, reward scoring and the multi-round match are done.)
- Bot's perfect-information-at-round-start gap (Section 7).
- Per-player visibility / online play (Section 15).
- Any richer UI beyond the two status Labels (Section 10) — e.g. a scrollable event log, slot-selection highlighting, or a dedicated "it's your turn" indicator beyond text.

## 17. Leave / Join Mid-Match (decided 2026-10-30)

**Rules (locked with the user):**
- Any player can leave mid-match: in-game Leave button -> "Leave match?" Yes/No popup. Closing or refreshing the tab counts as leaving (server sees the disconnect).
- A leaver is out: hand cleared at once, seat skipped from then on, their turn passes. Their reward score stays on the board marked "(left)" and counts in the final ranking. If they were the CABO caller the CABO lap is cancelled.
- The match continues while 2+ seats remain (humans AND bots count). With 1 seat left the match ends: a human survivor gets +20 (`caboWinReward`) and everyone returns to the setup screen; a bot survivor just ends it.
- Host leaves: the next human becomes host and the bots move to their machine (written 2026-11-04, see build order step 3; outside a match the host leaving still closes the room).
- Joining during a match: the joiner is a **spectator** who sees only what the table sees (face-down cards stay hidden). After the match everyone in the room, spectators included, fills the free human seats on the host's setup screen (auto), and the host picks bots and Start.

**Build order / status:**
1. Server (`cabo-server/server.js`): DONE 2026-10-30, untested. Host sends `{t:"started", value}`; joiners during a match become `waiting` (seat -1, no relays); when the match ends they get `{t:"seated", seat}`; roster carries `waiting` count. `NetClient`: `waiting`, `waitingCount`, `onSeated`, `setMatchStarted()`. `MenuScreen` shows the waiting notices.
2. Leave + elimination: DONE 2026-10-30, untested. `TurnManager`: `leavePopupNode`, `onLeaveButtonClicked/ConfirmClicked/CancelClicked`, `leaveMatch()`, `eliminateSeat()`, `endMatchEarly()`, `leftSeats`; host turns a vanished seat into a `{kind:"left"}` message applied from the net queue on every client (replaced the old "bot takes over"). `PlayerHand.setRewardScore(..., left)`. Editor to do: Leave button + popup (Yes/No) inside GameRoot, wire `leavePopupNode` and the three handlers; restart the server.
3. Host handover: WRITTEN 2026-11-04, untested. Server: `room.host`; if the host leaves mid-match (`room.started`) and another seated player exists, the lowest such seat becomes host and the roster (now carrying `host`) announces it; outside a match, or with nobody left, the room closes as before. When the match ends the new host moves back to seat 0 (`seated`), because the setup screen treats seat 1 as the host. Client: `NetClient.hostSeat`, `addHostChangeListener` (fires before the roster listeners); `TurnManager.onNetHostChanged` sets `netHost` (it then runs the bots and arbitrates the guests' actions, and its `onNetRoster` turns the old host's seat into a `{kind:"left"}`); queued host items carry `viaHost` so they replay as guest items even after the switch; `beginRound` only sends the deck order when it shuffled. A guest action in flight to the old host is lost (they click again). The new host must pick bots/humans again on the setup screen (the old host's choices stay on the old host's machine).
4. Spectators: WRITTEN 2026-11-04, untested. A joiner during a match is a spectator with `localSeat` -1 (no input, no private peeks, seat 1 at the bottom). The server relays every `to:"all"` message to waiting joiners too. They can't catch up mid-round, so they start at the next `round` packet, which now also carries `seats`, `rounds`, `scores`, `left` (`TurnManager.startMatchAsSpectator`, `startMatchCore(..., resume)`); until then they see the menu notice. Acts/left received before that are dropped. At match end `toSetup` + the server's `seated` put them in the lobby. No editor work needed (the Leave button/popup is reused). Restart the server. Possible upgrade: replay the round's action log so they can watch from the moment they join.
5. Hidden cards for spectators (NOT built, hardest): clients currently receive the real deck order (lockstep); spectators must only be sent public information.

## 18. Mobile / Screen Fit (landscape done 2026-10-30; portrait cancelled 2026-11-04)

**Cause of the old "pulled in" look:** the scene is 1920x1080 with `Camera.policy` `showAll`, so on other aspect ratios the frame shrinks to fit and full-screen images stop short of the edges.

**Done in the editor (user, 2026-10-30):**
- Every root/panel container and background has a full-stretch `UIWidget` (anchors 0..1, margins 0, Align to Safe Area off).
- The main game: `GameBackground` is an unstretched, centered 1920x1080 child (no widget) so the slots always line up with the art; a stretched back layer (same room image, `Art/Bg/Bg/BG (1).png`) goes behind it so the sides are not white (the scene clear color is white). Extended art (about 2560x1440, current picture unchanged in the centre) is the proper fix and is still to be painted.
- Widgets were REMOVED from slots, cards, hands, piles and anything placed on the art (CABO/Skip buttons, TV/table click spots, Host/Join/Start buttons...). Rule: if it is part of the picture, no widget; pure HUD (Leave, round label, mute, status line) = nearest edge/corner anchor (min = max, 0 / 0.5 / 1) + Align to Safe Area.
- Lesson: never put widgets on slot/card nodes (cards live in `CardPack` and are placed by world position, scripts move slots via `applyTableView`). Anchored Position is filled in by the Inspector when the anchor changes. Edit View is fixed at 1280x720; check other ratios with the Game view size.

**Portrait: CANCELLED (2026-11-04, user decision: no time before the deadline).** The game is landscape only. The portrait code was written and then removed again (`applyPortraitView`, `Card.setScaleFactor`, `PlayerHand.fitCard`); nothing of it remains in the scripts. Left in the editor by the user, harmless or to undo if wanted: `Canvas.supportOrientation` set to both, the saved design size 1080x1920 (press Apply Landscape on the Canvas to get 1920x1080 back in Edit View), and any `UIOrientationListener` poses added. If it is ever resumed: lay the hands out from `Camera.visibleWorldSize` in `applyTableView` (viewer's hand full size at the bottom, opponents in rows of two above, smaller) and re-snap cards when the shape changes.
- Also still open: extended room art; loading screen gate is done (`local/build/index.html`, opens on `window.__caboReady`).
## 19. UI Polish TODO (added 2026-11-06, none started)

1. **Settings button + panel:** a Settings button (menu and in-game) opens a panel with audio controls: **Music** and **VFX** (card sounds: slide, flip, select, swap, click). Build on the existing `GameAudio` mute toggles (`onToggleMusicClicked` / `onToggleSfxClicked`); decide mute switch vs volume slider, and whether the choice is saved locally (localStorage, like the player name).
2. **Circle timer per seat:** replace the single `TurnManager.turnTimerNode` Label with a circular countdown on each seat (ring around/next to the hand, only on the acting seat). Keep the existing rules (one clock per acting seat, turns red in the last 10 s, humans only, `turnTimeLimit` 0 = off). Needs a radial-fill sprite or drawn ring per `PlayerHand`; check the engine for a Sprite fill type or Graphics API.
3. **Small caption labels + draw-pile counter:** a small label above each table element (Draw pile, Discard pile, Skip ability button, CABO button, etc.), plus a **cards-left counter** on the draw pile (from `Deck`'s remaining count, updated on every draw and new round; matters because the round ends when the pile empties).
