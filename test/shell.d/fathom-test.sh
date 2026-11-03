#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const recency = requireFromRoot('shell/plugins/fathom/Recency.js')
const layout = requireFromRoot('shell/plugins/fathom/Layout.js')

// niri reports focus timestamps on the monotonic clock (seconds since boot),
// so ages are differences between stamps, never Date.now() arithmetic.
function win(id, atSeconds, extra) {
  return Object.assign({
    id: id,
    title: 'w' + id,
    app_id: 'app' + id,
    workspace_id: 1,
    is_focused: false,
    is_urgent: false,
    is_floating: false,
    focus_timestamp: atSeconds === null ? null : { secs: atSeconds, nanos: 0 }
  }, extra || {})
}

const windows = [
  win(1, 1000, { is_focused: true }),
  win(2, 990),
  win(3, 700),
  win(4, null)
]
const now = recency.newestStamp(windows)
assertEqual(now, 1000, 'the newest focus stamp is the field now')

const field = recency.buildField(windows, now, '1')
assertDeepEqual(field.map(e => e.id), [1, 2, 3, 4], 'field orders newest first, unknown last')
assertEqual(field[0].seconds, 0, 'the focused window is zero seconds away')
assertEqual(field[1].seconds, 10, 'age is the gap to the newest stamp')
assertEqual(field[3].seconds, Infinity, 'a window with no stamp is infinitely old')
assert(field[0].active && !field[1].active, 'only the focused window is active')

// Depth follows Fathom: log2(1 + seconds / 30), clamped to 8.
assertEqual(recency.depthForSeconds(0), 0, 'now is depth zero')
assertEqual(recency.depthForSeconds(30), 1, 'thirty seconds is one fathom')
assert(Math.abs(recency.depthForSeconds(90) - Math.log2(4)) < 1e-9, 'depth grows logarithmically')
assertEqual(recency.depthForSeconds(Infinity), 8, 'an unknown age is the deepest')

// A focused window whose stamp was debounced away must still sort first.
const debounced = recency.buildField([win(7, null, { is_focused: true }), win(8, 500)], 500, '7')
assertDeepEqual(debounced.map(e => e.id), [7, 8], 'the focused window leads even without a stamp')

assertEqual(recency.initialSelection(0, 1), -1, 'no windows means no selection')
assertEqual(recency.initialSelection(1, 1), 0, 'a single window selects itself')
assertEqual(recency.initialSelection(4, 1), 1, 'opening with a step lands on the previous window')
assertEqual(recency.initialSelection(4, -1), 3, 'opening backwards lands on the oldest')

assertEqual(recency.stepSelection(0, 1, 4), 1, 'a step moves forward')
assertEqual(recency.stepSelection(3, 1, 4), 0, 'stepping past the end wraps')
assertEqual(recency.stepSelection(0, -1, 4), 3, 'stepping before the start wraps')
assertEqual(recency.stepSelection(-1, 1, 4), 1, 'a missing selection steps from the front')

assertEqual(recency.stampSeconds({ secs: 12, nanos: 500000000 }), 12.5, 'nanoseconds fold into the stamp')
assertEqual(recency.stampSeconds(null), null, 'a missing stamp is null, not zero')
// The depth stack: the selection sits in front, older cards step back, shrink
// and fade, and the cards the camera passed fade out to the left.
const stage = layout.deepStage(1600, 1000, 24, 96, 1.6, 0)
const front = layout.deepPlane(stage, 0)
assertEqual(front.scale, 1, 'the front card is unscaled')
assertEqual(front.opacity, 1, 'the front card is opaque')
const back = layout.deepPlane(stage, 1)
assert(back.width < front.width, 'a card one step back is narrower')
assert(back.y < front.y, 'a card one step back sits higher')
assert(back.x > front.x, 'a card one step back sits further right')
const passed = layout.deepPlane(stage, -1)
assert(passed.opacity < 1, 'a passed card is faded')
assert(passed.scale > 1, 'a passed card grows as it goes behind the camera')
assertEqual(layout.deepPlane(stage, layout.VISIBLE_STEPS + 1).opacity, 0, 'cards beyond the visible depth are gone')
