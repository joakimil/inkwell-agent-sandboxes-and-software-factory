# Inkwell save freshness and unsaved-change warning

## What changed

`apps/inkwell/public/app.js` now tracks the time of the most recent successful post save and displays a relative save label once the save is settled:

- Under five seconds: `saved just now`
- Five seconds through 59 seconds: `saved Ns ago`
- Minutes through 59 minutes: `saved Nm ago`
- One hour or more: `saved Nh ago`

The existing transient states remain explicit: while a debounce timer or request is active, the indicator continues to show its supplied state such as `saving…`; failed saves show `save failed`. The timestamp is recorded when the PUT request succeeds, and the relative label is refreshed every 30 seconds without issuing another save.

A `beforeunload` listener now prevents leaving the page silently when either a debounced save is waiting or a save request is in flight. It calls `preventDefault()` and sets `returnValue`, allowing the browser to display its own confirmation prompt. There is no prompt when neither unsaved-work condition is active.

## Where it lives

All of this behavior is in `apps/inkwell/public/app.js`:

- `formatSavedAgo()` formats the elapsed time.
- `setSaveState()` chooses between the relative label and the current transient state.
- `startSavedAgoTicker()` updates the settled label on a 30-second interval.
- `save()` records `lastSavedAt` after a successful API update.
- The boot section starts the ticker and installs the `beforeunload` guard.

## How to verify

1. Open Inkwell and edit a post. During the debounce/request, confirm the indicator shows `saving…`; after the request succeeds, confirm it changes to `saved just now`.
2. Leave the page open for at least five seconds and confirm the label advances to `saved 5s ago` (or the current elapsed seconds). Wait across a 30-second interval to confirm it refreshes without changing the post.
3. Make another edit and immediately attempt to close or navigate away. Confirm the browser’s native unsaved-changes dialog appears while the debounce or request is active.
4. After the save settles, attempt to leave again and confirm the guard does not prompt.
5. Force an unsuccessful save if a suitable API failure setup is available; confirm `save failed` remains visible rather than being replaced by a timestamp.

No separate test or configuration file was changed by this work.
