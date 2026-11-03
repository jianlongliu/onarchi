
// Geometry for the Alt-Tab field's depth stack.
//
// Adapted from Fathom (src/Layout.js) by Maarten Tolhuijs, MIT licensed. Only
// the two functions this field uses are kept; the workspace map, the sounding
// line and the passing-camera helpers live upstream and are not used here.
//
// Every window is a card of the same shape, so the stack steps evenly whatever
// the windows' own shapes are. The selection's card sits in the front box.
// Each card behind it is scaled by SIZE_Q per step and its top-right corner
// moves up and to the right by a step that itself shrinks by POS_Q, so every
// card shows above the card in front of it. Cards the camera has passed grow
// and slide out to the lower left, fading within PASSED_FADE steps.

var SIZE_Q = 0.82;          // card scale per step behind the camera
var POS_Q = 0.86;           // how much each step's offset shrinks
var RISE = 0.1;             // first step upward, as a share of the card height
var PASSED_FADE = 0.6;      // steps over which a passed card fades out
var PASSED_GROWTH = 0.2;    // extra scale of a card one step past
var VISIBLE_STEPS = 5;      // cards further back fade out

function clamp(value, low, high) {
    return Math.max(low, Math.min(high, value));
}

// The sum of the step offsets up to r steps back (continuous in r).
function stepSum(r) {
    return r <= 0 ? 0 : (1 - Math.pow(POS_Q, r)) / (1 - POS_Q);
}

// The front box for a screen of width x height, between `top` and
// `height - bottom`, for cards of `aspect`. The whole stack (front card plus
// the cards behind it) is centered in that area.
function deepStage(width, height, top, bottom, aspect, left) {
    var inset = Math.max(0, Number(left) || 0);
    var a = clamp(Number(aspect) || 1.6, 1.2, 2.4);
    var available = Math.max(1, height - top - bottom);
    var reach = stepSum(VISIBLE_STEPS);
    var frontHeight = available / (1 + RISE * reach);
    var frontWidth = frontHeight * a;
    if (frontWidth > width * 0.5) {
        frontWidth = width * 0.5;
        frontHeight = frontWidth / a;
    }
    var room = width - inset;
    if (frontWidth > room * 0.55) {
        frontWidth = room * 0.55;
        frontHeight = frontWidth / a;
    }
    var margin = width * 0.03;
    var spread = Math.max(0, Math.min(frontWidth * 0.85, room - margin * 2 - frontWidth));
    var stackHeight = frontHeight * (1 + RISE * reach);
    var stackTop = top + (available - stackHeight) / 2;
    return {
        frontX: inset + (room - frontWidth - spread) / 2 + frontWidth / 2,
        frontY: stackTop + RISE * frontHeight * reach + frontHeight / 2,
        frontWidth: frontWidth,
        frontHeight: frontHeight,
        stepX: reach > 0 ? spread / reach : 0,
        stepY: RISE * frontHeight
    };
}

// stage: from deepStage. r: the card's slot minus the camera slot (real,
// negative once passed). Returns the card's center, size, scale, opacity, z.
function deepPlane(stage, r) {
    if (r < 0) {
        var passed = Math.min(1.5, -r);
        var grow = 1 + PASSED_GROWTH * Math.min(1, passed);
        return {
            x: stage.frontX - passed * stage.frontWidth * 0.5,
            y: stage.frontY + passed * stage.frontHeight * 0.12,
            width: stage.frontWidth * grow,
            height: stage.frontHeight * grow,
            scale: grow,
            opacity: clamp(1 - passed / PASSED_FADE, 0, 1),
            z: 1000 + passed
        };
    }
    var scale = Math.pow(SIZE_Q, r);
    var sum = stepSum(r);
    var width = stage.frontWidth * scale;
    var height = stage.frontHeight * scale;
    var right = stage.frontX + stage.frontWidth / 2 + stage.stepX * sum;
    var top = stage.frontY - stage.frontHeight / 2 - stage.stepY * sum;
    return {
        x: right - width / 2,
        y: top + height / 2,
        width: width,
        height: height,
        scale: scale,
        opacity: clamp(VISIBLE_STEPS + 1 - r, 0, 1),
        z: 1000 - r
    };
}


// ------------------------------------------------------------ the sounding line

// The gauge beside the Deep reads depth the way a lead line reads water: the
// surface (depth 0, now) at `top`, MAX_DEPTH at `bottom`.
function soundingY(depth, top, bottom, maxDepth) {
    var limit = maxDepth > 0 ? maxDepth : 8;
    var value = Math.max(0, Math.min(limit, Number(depth) || 0));
    return top + (bottom - top) * value / limit;
}

// One mark per window: its y on the gauge and a column, so windows at nearly
// the same depth sit side by side instead of on top of each other. Beyond
// `maxColumns` a mark is hidden and the last visible mark of the row counts
// them (`more`), so a crowded depth says how crowded it is.
function soundingMarks(depths, top, bottom, maxDepth, spacing, maxColumns) {
    var list = depths || [];
    var gap = spacing > 0 ? spacing : 6;
    var limit = maxColumns > 0 ? Math.floor(maxColumns) : Infinity;
    var marks = [];
    var rows = [];
    for (var i = 0; i < list.length; i++) {
        var y = soundingY(list[i], top, bottom, maxDepth);
        var row = null;
        for (var j = 0; j < rows.length; j++) {
            if (Math.abs(rows[j].y - y) < gap) {
                row = rows[j];
                break;
            }
        }
        if (!row) {
            row = { y: y, count: 0, last: -1 };
            rows.push(row);
        }
        var column = row.count;
        row.count++;
        var hidden = column >= limit;
        var mark = { y: row.y, column: column, hidden: hidden, more: 0 };
        if (hidden) marks[row.last].more++;
        else row.last = marks.length;
        marks.push(mark);
    }
    return marks;
}

// ------------------------------------------------------------ the map

// The rectangle a workspace's minimap has to show: the viewport, grown to
// include every window outside it. A scrolling layout parks windows to the
// left and right of the screen; the whole strip is shown, compressed.
function minimapBounds(viewport, windows) {
    var left = viewport.x;
    var top = viewport.y;
    var right = viewport.x + viewport.width;
    var bottom = viewport.y + viewport.height;
    var list = windows || [];
    for (var i = 0; i < list.length; i++) {
        var w = list[i];
        if (!w || !(w.width > 0) || !(w.height > 0) || !isFinite(w.x) || !isFinite(w.y)) continue;
        left = Math.min(left, w.x);
        top = Math.min(top, w.y);
        right = Math.max(right, w.x + w.width);
        bottom = Math.max(bottom, w.y + w.height);
    }
    return { x: left, y: top, width: Math.max(1, right - left), height: Math.max(1, bottom - top) };
}

// The shell imports this file as a QML library; the tests load it with node.
if (typeof module !== "undefined") {
  module.exports = {
    deepStage: deepStage,
    deepPlane: deepPlane,
    stepSum: stepSum,
    soundingY: soundingY,
    soundingMarks: soundingMarks,
    minimapBounds: minimapBounds,
    VISIBLE_STEPS: VISIBLE_STEPS
  }
}
