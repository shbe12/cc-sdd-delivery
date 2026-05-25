# Order Map Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the 3D order map look polished — dusk lighting, atmospheric fog, a branded PizzApp pin, and a one-time fly-in — on both the manager and rider order screens.

**Architecture:** Presentation-only change. The single shared Stimulus `map` controller (`app/javascript/controllers/map_controller.js`) gains live Standard-style config (`lightPreset`/`fog`), a custom DOM marker, and a camera `easeTo` fly-in that respects `prefers-reduced-motion`. Marker styling lives in a new SCSS component. No Ruby domain code (model/controllers/views/seeds) changes — the views already wire `lat`/`lng`/`api-key` into the controller, and CDMX geocoding is already done on this branch.

**Tech Stack:** Rails 8.1, Hotwire/Stimulus via importmap (no JS build/test runner), `mapbox-gl@3.7.0` (pinned in `config/importmap.rb`), Bootstrap/SCSS via dartsass, Minitest, Playwright MCP for live verification.

---

## Why verification is split (read first)

This app has **no JavaScript test runner** (importmap, no Node/`package.json`). So:

- **Minitest** can only guard the *server-rendered wiring* (the `.order-map` element + its `data-*` attributes). That guard already passes today; Task 1 locks it so the refactor can't silently break the contract the JS depends on.
- The **actual JS behavior** (dusk preset, fog, branded pin, fly-in, reduced-motion) is verified **live with Playwright MCP** against the running app in Task 4. That is the real red→green test for this feature: run the acceptance checks against current `master`-style code and they FAIL (preset is `day`, fog is null, default SVG pin, no fly-in); run them after Tasks 2–3 and they PASS.

Do not add a JS unit-test framework — that is explicitly out of scope.

## File Structure

- **Modify** `app/javascript/controllers/map_controller.js` — the whole map behavior. One file, one responsibility (render the destination map).
- **Create** `app/assets/stylesheets/components/_order_map_marker.scss` — styles for the branded marker element (pin + pulse keyframes). New focused component file.
- **Modify** `app/assets/stylesheets/components/_index.scss` — add the `@import` for the new component.
- **Modify** `test/integration/manager_orders_test.rb` — add one wiring-guard test.
- **Modify** `test/integration/rider_orders_test.rb` — add one wiring-guard test.

---

### Task 1: Wiring-guard tests for the order map (manager + rider)

These guard the server-rendered contract the JS controller depends on (`.order-map` with `data-controller="map"` and the lat/lng data values). They PASS now and must keep passing after the refactor. In test, `config/initializers/geocoder.rb` stubs every address to CDMX center, so created orders always have `latitude`/`longitude` and the map renders.

**Files:**
- Modify: `test/integration/manager_orders_test.rb`
- Modify: `test/integration/rider_orders_test.rb`

- [ ] **Step 1: Add the manager wiring test**

In `test/integration/manager_orders_test.rb`, add this test inside the class (e.g. after the existing `show ...` test, before the final `end`):

```ruby
  test "show wires the order map element with destination coordinates" do
    order = create_order(status: :assigned, rider: @rider)
    get manager_order_path(order)
    assert_response :success
    assert_select ".order-map[data-controller='map']"
    assert_select ".order-map[data-map-lat-value]"
    assert_select ".order-map[data-map-lng-value]"
  end
```

- [ ] **Step 2: Add the rider wiring test**

In `test/integration/rider_orders_test.rb`, add this test inside the class (before the final `end`):

```ruby
  test "show wires the order map element with destination coordinates" do
    order = create_order(rider: @rider, status: :assigned)
    get rider_order_path(order)
    assert_response :success
    assert_select ".order-map[data-controller='map']"
    assert_select ".order-map[data-map-lat-value]"
    assert_select ".order-map[data-map-lng-value]"
  end
```

- [ ] **Step 3: Run the two new tests — expect PASS (guard for existing wiring)**

Run:
```bash
bin/rails test test/integration/manager_orders_test.rb test/integration/rider_orders_test.rb
```
Expected: all tests pass (the new ones included). If a new test FAILS, the view stopped rendering `.order-map` — fix the view wiring before continuing.

- [ ] **Step 4: Run RuboCop on the changed test files**

Run:
```bash
bin/rubocop test/integration/manager_orders_test.rb test/integration/rider_orders_test.rb
```
Expected: no offenses.

- [ ] **Step 5: Commit**

```bash
git add test/integration/manager_orders_test.rb test/integration/rider_orders_test.rb
git commit -m "test: guard order map wiring on manager and rider show"
```

---

### Task 2: Branded PizzApp marker styles (SCSS component)

A green teardrop pin (`$brand` = `#16A34A`, "verde albahaca") with a 🍕 glyph and a pulsing ring. The marker element is built in JS (Task 3) and gets these classes. `$brand` is in scope because `application.scss` imports `config/colors` before `components/index`.

**Files:**
- Create: `app/assets/stylesheets/components/_order_map_marker.scss`
- Modify: `app/assets/stylesheets/components/_index.scss`

- [ ] **Step 1: Create the marker component file**

Create `app/assets/stylesheets/components/_order_map_marker.scss` with exactly:

```scss
// Branded PizzApp destination marker rendered as a Mapbox custom marker element.
// The element is created in app/javascript/controllers/map_controller.js and
// anchored "bottom", so the teardrop tip sits on the destination coordinate.
.order-pin {
  position: relative;
  width: 32px;
  height: 40px;
}

.order-pin__dot {
  position: absolute;
  left: 50%;
  bottom: 6px;
  width: 30px;
  height: 30px;
  margin-left: -15px;
  background: linear-gradient(135deg, $brand, #3fd07f);
  border: 2px solid #fff;
  border-radius: 50% 50% 50% 0;
  transform: rotate(45deg);
  box-shadow: 0 6px 14px rgba(0, 0, 0, 0.35);
  display: grid;
  place-items: center;
}

.order-pin__glyph {
  transform: rotate(-45deg);
  font-size: 15px;
  line-height: 1;
}

.order-pin__pulse {
  position: absolute;
  left: 50%;
  bottom: -14px;            // centers the ring on the tip (the coordinate)
  width: 28px;
  height: 28px;
  margin-left: -14px;
  border-radius: 50%;
  background: rgba($brand, 0.35);
  animation: order-pin-pulse 1.8s ease-out infinite;
}

@keyframes order-pin-pulse {
  0%   { transform: scale(0.4); opacity: 0.9; }
  100% { transform: scale(2);   opacity: 0; }
}
```

- [ ] **Step 2: Register the component in the index**

In `app/assets/stylesheets/components/_index.scss`, add this line at the end (after `@import "navbar";`):

```scss
@import "order_map_marker";
```

- [ ] **Step 3: Verify the stylesheet compiles**

Run:
```bash
bin/rails dartsass:build
```
Expected: exits 0 with no Sass error (the new `@import` resolves and `$brand`/`rgba($brand, …)` compile). If `dartsass:build` is unavailable, instead confirm compilation when the server boots in Task 4 (a Sass error would 500 the page).

- [ ] **Step 4: Commit**

```bash
git add app/assets/stylesheets/components/_order_map_marker.scss app/assets/stylesheets/components/_index.scss
git commit -m "style: branded PizzApp order-map marker"
```

---

### Task 3: Rewrite the map controller (dusk + fog + brand pin + fly-in)

Replace the controller body. Keeps the `apiKey` guard, the `values`, and `disconnect`. Adds: wide→tilted fly-in (skipped under reduced-motion), `dusk` light preset + fog applied on `style.load`, and the branded marker element from Task 2.

**Files:**
- Modify: `app/javascript/controllers/map_controller.js`

- [ ] **Step 1: Replace the controller with the new implementation**

Overwrite `app/javascript/controllers/map_controller.js` with exactly:

```js
import { Controller } from "@hotwired/stimulus"
import mapboxgl from "mapbox-gl"

// Renders the delivery destination on a polished 3D Mapbox map:
// dusk lighting + atmospheric fog + a branded PizzApp pin + a one-time fly-in.
// Shared by the manager and rider order "show" screens.
export default class extends Controller {
  static values = { apiKey: String, lat: Number, lng: Number }

  connect() {
    if (!this.apiKeyValue) return
    mapboxgl.accessToken = this.apiKeyValue

    const center = [this.lngValue, this.latValue]
    const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    const finalView = { zoom: 15.5, pitch: 60, bearing: -17 }

    this.map = new mapboxgl.Map({
      container: this.element,
      style: "mapbox://styles/mapbox/standard", // 3D buildings + lighting (mapbox-gl v3)
      center,
      // Start wide & flat so we can fly in; under reduced-motion start at the final view.
      zoom: reduceMotion ? finalView.zoom : 13.5,
      pitch: reduceMotion ? finalView.pitch : 0,
      bearing: reduceMotion ? finalView.bearing : 0
    })

    // Standard-style config must be applied after the style finishes loading.
    this.map.on("style.load", () => {
      this.map.setConfigProperty("basemap", "lightPreset", "dusk")
      this.map.setFog({
        range: [1, 12],
        color: "#e6eef8",
        "high-color": "#9ec1ec",
        "horizon-blend": 0.25,
        "space-color": "#0c1330",
        "star-intensity": 0.05
      })
    })

    // One-time cinematic fly-in to the tilted view (skipped under reduced-motion).
    if (!reduceMotion) {
      this.map.on("load", () => {
        this.map.easeTo({ center, ...finalView, duration: 2800, essential: true })
      })
    }

    const pin = document.createElement("div")
    pin.className = "order-pin"
    pin.innerHTML =
      '<span class="order-pin__pulse"></span>' +
      '<span class="order-pin__dot"><span class="order-pin__glyph">🍕</span></span>'

    new mapboxgl.Marker({ element: pin, anchor: "bottom" })
      .setLngLat(center)
      .addTo(this.map)
  }

  disconnect() {
    this.map?.remove()
  }
}
```

- [ ] **Step 2: Run the full Minitest suite — expect GREEN**

Run:
```bash
bin/rails test
```
Expected: all tests pass. No Ruby changed, so the suite (including Task 1's guards) stays green; this confirms the JS edit didn't break server-rendered behavior.

- [ ] **Step 3: Run RuboCop — expect clean**

Run:
```bash
bin/rubocop
```
Expected: no offenses. (RuboCop does not lint JS/SCSS; this confirms nothing Ruby regressed.)

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/map_controller.js
git commit -m "feat: polish order map (dusk, fog, brand pin, fly-in)"
```

---

### Task 4: Live Playwright verification (the real acceptance test)

Verify the JS behavior against the running app for **both** roles. This is the red→green test: run the evaluate check below before Tasks 2–3 and it fails; run it now and it passes.

Requires `MAPBOX_API_KEY` in `.env` (present in dev).

- [ ] **Step 1: Seed geocoded orders and boot the server**

```bash
bin/rails db:seed:replant
bin/dev
```
Expected: seeds print "Done: 3 users, 5 products, 5 orders." and the server listens on http://localhost:3000. Seeded orders sit on the Paseo de la Reforma corridor (tall towers → 3D shows well). Login: manager `manager@pizzapp.test`, rider `pedro@pizzapp.test`, password `password123` for both.

- [ ] **Step 2: Log in as manager and open an order (Playwright MCP)**

- `mcp__playwright__browser_navigate` → `http://localhost:3000/users/sign_in`
- Fill the Devise form (`#user_email` = `manager@pizzapp.test`, `#user_password` = `password123`) and submit.
- `mcp__playwright__browser_navigate` → `http://localhost:3000/manager/orders`, then click the first `.order-card` to open its show page (any seeded order has coordinates).
- `mcp__playwright__browser_wait_for` time `5` (let `style.load`, fog, and the 2.8s fly-in settle).

- [ ] **Step 3: Assert the live map state (acceptance criteria 1–4, 6 for manager)**

`mcp__playwright__browser_evaluate` with:
```js
() => {
  const el = document.querySelector('.order-map')
  if (!el) return { error: 'no .order-map' }
  const m = window.Stimulus.getControllerForElementAndIdentifier(el, 'map').map
  return {
    pitch: Math.round(m.getPitch()),
    zoom: +m.getZoom().toFixed(1),
    lightPreset: m.getConfigProperty('basemap', 'lightPreset'),
    fog: m.getFog() != null,
    hasBrandPin: !!el.querySelector('.order-pin'),
    hasDefaultPin: !!el.querySelector('.mapboxgl-marker svg')
  }
}
```
Expected: `{ pitch: 60, zoom: 15.5, lightPreset: "dusk", fog: true, hasBrandPin: true, hasDefaultPin: false }`.

- [ ] **Step 4: Screenshot the manager map element (not fullPage)**

`mcp__playwright__browser_take_screenshot` with `target: ".order-map"`, `filename: "verify-manager-map.png"`. Confirm visually: warm dusk sky, lit 3D towers, green 🍕 pin on the destination.

- [ ] **Step 5: Repeat for the rider role**

Sign out (navigate to `http://localhost:3000/users/sign_out` via a `button_to`/link, or clear cookies and re-navigate to sign-in), log in as `pedro@pizzapp.test` / `password123`, open one of his deliveries from `http://localhost:3000/rider/orders`, wait `5`, and re-run the Step 3 evaluate. Expected: identical result (criterion 6 — same controller drives both). Screenshot as `verify-rider-map.png`.

- [ ] **Step 6: Verify reduced-motion (acceptance criterion 5)**

Using `mcp__playwright__browser_run_code_unsafe`, emulate reduced motion and reload, then assert the final view is reached with no fly-in animation:
```js
await page.emulateMedia({ reducedMotion: 'reduce' })
await page.reload()
await page.waitForTimeout(2500)
return await page.evaluate(() => {
  const el = document.querySelector('.order-map')
  const m = window.Stimulus.getControllerForElementAndIdentifier(el, 'map').map
  return { pitch: Math.round(m.getPitch()), zoom: +m.getZoom().toFixed(1) }
})
```
Expected: `{ pitch: 60, zoom: 15.5 }` essentially immediately (no ~3s tilt-up), confirming the `reduceMotion` branch starts at the final view and skips `easeTo`. If `browser_run_code_unsafe`/`emulateMedia` is unavailable, instead confirm by code inspection that the `reduceMotion` branch sets the initial `zoom/pitch/bearing` to `finalView` and the `easeTo` is guarded by `if (!reduceMotion)`.

- [ ] **Step 7: If any criterion fails, fix and re-verify**

If a check fails (e.g. the pin tip is visibly off the coordinate, or fog is too strong), adjust the relevant file (`_order_map_marker.scss` offsets, or the `setFog`/`easeTo` params in the controller), re-run the failing evaluate, then amend or add a follow-up commit:
```bash
git add -A && git commit -m "fix: tune order map marker/fog"
```
Stop the server (`Ctrl-C` on `bin/dev`) when done.

---

### Task 5: Final pipeline and branch wrap-up

- [ ] **Step 1: Run the full local CI**

Run:
```bash
bin/ci
```
Expected: green — setup, RuboCop, the three security scanners, the Minitest suite, and `db:seed:replant` all pass. (`db:seed:replant` needs `MAPBOX_API_KEY`; without it geocoding no-ops non-fatally — preexisting behavior.)

- [ ] **Step 2: Finish the branch**

Invoke the **superpowers:finishing-a-development-branch** skill to choose how to integrate (PR vs merge). The user follows an SDD workflow and expects a PR for this feature (spec + plan already committed on `fix/cdmx-geocoding-3d-map`). Confirm with the user whether this rides the current branch's PR or gets its own.

---

## Self-review (done by planner)

- **Spec coverage:** dusk preset ✓ (T3), fog ✓ (T3), brand marker ✓ (T2+T3), fly-in + reduced-motion ✓ (T3, verified T4 S6), both roles ✓ (shared controller; guarded T1, verified T4 S5), Minitest green + RuboCop clean ✓ (T1/T3/T5), wiring guard ✓ (T1), Playwright acceptance criteria 1–6 ✓ (T4). No spec requirement left without a task.
- **Placeholders:** none — every code/SCSS/JS block and command is complete.
- **Type/name consistency:** marker classes `.order-pin` / `.order-pin__dot` / `.order-pin__glyph` / `.order-pin__pulse` and keyframe `order-pin-pulse` match across the SCSS (T2), the JS `innerHTML` (T3), and the Playwright selector `.order-pin` (T4). Config calls `setConfigProperty('basemap','lightPreset','dusk')` / `getConfigProperty('basemap','lightPreset')` and `setFog`/`getFog` are paired and exist in `mapbox-gl@3.7.0`.
