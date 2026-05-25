# Rider mobile-first Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the rider experience mobile-first — a compact top-bar layout and an order-detail screen where the map is the protagonist — without changing anything the manager sees.

**Architecture:** The rider gets its **own layout** (`Rider::BaseController` declares `layout "rider"`), so the shared `application.html.erb` / sidebar / `_app_shell.scss` are never touched. All new CSS is namespaced under `.rider-shell` (a class that only exists in the rider layout) or under `rider-*` classes, guaranteeing the manager renders byte-identically. The order detail is restructured to a map-protagonist layout with the action button fixed at the bottom on mobile; the items `<table>` becomes a `<ul>`.

**Tech Stack:** Rails 8.1, ERB views, SCSS (sass split into `config/`/`components/`/`pages/`, imported by `application.scss`), Mapbox GL via the existing `map` Stimulus controller, Minitest integration tests (`Devise::Test::IntegrationHelpers`, geocoder stubbed to CDMX coords in test), Playwright MCP for E2E.

**Spec:** `docs/superpowers/specs/2026-05-25-rider-mobile-first-design.md`

**Confirmed assumption:** the rider uses the top bar at **all** screen sizes (it stops seeing the sidebar on desktop too). This avoids duplicating the sidebar into the rider layout.

---

## File Structure

**New files**
- `app/views/layouts/rider.html.erb` — the rider-only HTML layout (duplicated `<head>` so the shared layout stays intact; `<body>` with `.rider-topbar` + `.rider-shell__main`). Responsibility: rider page chrome.
- `app/assets/stylesheets/pages/_rider.scss` — ALL rider styling, namespaced under `.rider-shell`. Responsibility: rider mobile-first styles (topbar, shell, map-protagonist detail, items list, sticky action).

**Modified files**
- `app/controllers/rider/base_controller.rb` — add `layout "rider"` (one line). Covers the whole `rider` namespace.
- `app/views/rider/orders/show.html.erb` — rewrite to map-protagonist + items `<ul>` + sticky action; rider-namespaced classes.
- `app/assets/stylesheets/pages/_index.scss` — add `@import "rider";` (one additive line; the only shared-stylesheet touch).
- `test/integration/rider_orders_test.rb` — add layout + structure tests.
- `test/integration/manager_orders_test.rb` — add one regression test (manager keeps the sidebar, gets no rider chrome).

**Explicitly NOT touched** (manager isolation): `app/views/layouts/application.html.erb`, `app/views/shared/_sidebar.html.erb`, `app/assets/stylesheets/components/_app_shell.scss`, `app/assets/stylesheets/pages/_orders.scss`, anything under `app/views/manager/` or `app/controllers/manager/`.

---

## Task 1: Rider top-bar layout

Give the rider its own layout (top bar at all sizes); leave the manager on the shared layout.

**Files:**
- Modify: `app/controllers/rider/base_controller.rb`
- Create: `app/views/layouts/rider.html.erb`
- Create: `app/assets/stylesheets/pages/_rider.scss`
- Modify: `app/assets/stylesheets/pages/_index.scss`
- Test: `test/integration/rider_orders_test.rb`, `test/integration/manager_orders_test.rb`

- [ ] **Step 1: Write the failing test (rider uses top-bar layout, not sidebar)**

Add to `test/integration/rider_orders_test.rb` (inside the class, after the last test):

```ruby
  test "rider pages use the top-bar layout, not the shared sidebar" do
    order = create_order(rider: @rider, status: :assigned)

    get rider_orders_path
    assert_response :success
    assert_select ".rider-topbar"
    assert_select ".sidebar", false

    get rider_order_path(order)
    assert_response :success
    assert_select ".rider-topbar"
    assert_select ".sidebar", false
  end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bin/rails test test/integration/rider_orders_test.rb -n "/top-bar layout/"`
Expected: FAIL — `.rider-topbar` not found and `.sidebar` present (rider still uses `application.html.erb`).

- [ ] **Step 3: Create the rider layout**

Create `app/views/layouts/rider.html.erb`:

```erb
<!DOCTYPE html>
<html>
  <head>
    <title><%= content_for(:title) || "PizzApp" %></title>
    <meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no, viewport-fit=cover">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="application-name" content="Cc Sdd Delivery">
    <meta name="mobile-web-app-capable" content="yes">
    <%= csrf_meta_tags %>
    <%= csp_meta_tag %>

    <%= yield :head %>

    <link rel="icon" href="/icon.png" type="image/png">
    <link rel="icon" href="/icon.svg" type="image/svg+xml">
    <link rel="apple-touch-icon" href="/icon.png">

    <link href="https://api.mapbox.com/mapbox-gl-js/v3.7.0/mapbox-gl.css" rel="stylesheet">
    <%= stylesheet_link_tag "application", "data-turbo-track": "reload" %>
    <%= javascript_importmap_tags %>
  </head>

  <body>
    <div class="rider-shell">
      <header class="rider-topbar">
        <%= link_to rider_orders_path, class: "rider-topbar__brand" do %>
          <span class="rider-topbar__logo">🍕</span> PizzApp
        <% end %>
        <div class="rider-topbar__user">
          <span class="rider-topbar__avatar"><%= current_user.email.first(2).upcase %></span>
          <%= link_to "Salir", destroy_user_session_path,
                data: { turbo_method: :delete }, class: "rider-topbar__logout" %>
        </div>
      </header>

      <main class="rider-shell__main">
        <%= render "shared/flashes" %>
        <%= yield %>
      </main>
    </div>
  </body>
</html>
```

(`Rider::BaseController` already requires an authenticated rider, so the layout can assume `current_user` exists.)

- [ ] **Step 4: Point the rider namespace at the new layout**

In `app/controllers/rider/base_controller.rb`, add `layout "rider"` so the class reads:

```ruby
module Rider
  class BaseController < ApplicationController
    layout "rider"
    before_action :require_rider

    private

    def require_rider
      redirect_to root_path, alert: "No tienes acceso a esa sección." unless current_user.rider?
    end
  end
end
```

- [ ] **Step 5: Create the rider stylesheet (topbar + shell) and register it**

Create `app/assets/stylesheets/pages/_rider.scss`:

```scss
// Rider mobile-first experience. Everything is namespaced under .rider-shell so the
// shared manager layout (sidebar) is never affected.

.rider-shell {
  min-height: 100vh;
  min-height: 100dvh;
  display: flex;
  flex-direction: column;
  background: $bg;
}

.rider-topbar {
  position: sticky;
  top: 0;
  z-index: 20;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 12px 16px;
  padding-top: calc(12px + env(safe-area-inset-top));
  background: #fff;
  border-bottom: 1px solid $line;

  &__brand {
    display: flex;
    align-items: center;
    gap: 9px;
    font-family: $headers-font;
    font-weight: 800;
    font-size: 17px;
    color: $ink;
    text-decoration: none;
  }
  &__logo {
    width: 30px;
    height: 30px;
    border-radius: 10px;
    display: grid;
    place-items: center;
    font-size: 16px;
    background: linear-gradient(140deg, $brand, lighten($brand, 18%));
    box-shadow: 0 6px 16px rgba($brand, 0.35);
  }
  &__user {
    display: flex;
    align-items: center;
    gap: 12px;
  }
  &__avatar {
    width: 32px;
    height: 32px;
    border-radius: 10px;
    display: grid;
    place-items: center;
    color: #fff;
    font-weight: 700;
    font-size: 11px;
    background: linear-gradient(135deg, #5B72E8, #9B5BE8);
  }
  &__logout {
    color: $muted;
    font-size: 13px;
    font-weight: 600;
    text-decoration: none;
    &:hover { color: $ink; }
  }
}

.rider-shell__main {
  flex: 1;
  width: 100%;
  max-width: 640px;
  margin: 0 auto;
  padding: 16px;
  padding-bottom: calc(16px + env(safe-area-inset-bottom));
}

// The rider list (Mis entregas) — relax the shared max-width on mobile.
.rider-shell .rider-list { max-width: none; }
```

Then add the import to `app/assets/stylesheets/pages/_index.scss` (keep existing lines, append):

```scss
// Import page-specific CSS files here.
@import "home";
@import "auth";
@import "orders";
@import "rider";
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `bin/rails test test/integration/rider_orders_test.rb -n "/top-bar layout/"`
Expected: PASS.

- [ ] **Step 7: Add the manager regression guard**

Add to `test/integration/manager_orders_test.rb` (inside the class):

```ruby
  test "manager keeps the shared sidebar layout and gets no rider chrome" do
    get manager_orders_path
    assert_response :success
    assert_select ".sidebar"
    assert_select ".rider-topbar", false
  end
```

- [ ] **Step 8: Run the manager regression test**

Run: `bin/rails test test/integration/manager_orders_test.rb -n "/no rider chrome/"`
Expected: PASS (manager untouched).

- [ ] **Step 9: Commit**

```bash
git add app/controllers/rider/base_controller.rb app/views/layouts/rider.html.erb \
        app/assets/stylesheets/pages/_rider.scss app/assets/stylesheets/pages/_index.scss \
        test/integration/rider_orders_test.rb test/integration/manager_orders_test.rb
git commit -m "$(cat <<'EOF'
feat(rider): dedicated top-bar layout, manager untouched

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Order detail — map protagonist + items list

Restructure `rider#show` so the map leads, the action button is fixed at the bottom on mobile, and items render as a list. No call/navigate buttons.

**Files:**
- Modify: `app/views/rider/orders/show.html.erb`
- Modify: `app/assets/stylesheets/pages/_rider.scss`
- Test: `test/integration/rider_orders_test.rb`

- [ ] **Step 1: Write the failing tests (items as list, no call/navigate)**

Add to `test/integration/rider_orders_test.rb`:

```ruby
  test "show renders order items as a list, not a table" do
    order = create_order(rider: @rider, status: :assigned)
    get rider_order_path(order)
    assert_response :success
    assert_select "ul.rider-items li.rider-items__row"
    assert_select "li.rider-items__row--total", text: /Total/
    assert_select "table.order-items", false
  end

  test "show has no call or navigate action buttons" do
    order = create_order(rider: @rider, status: :assigned)
    get rider_order_path(order)
    assert_response :success
    assert_select "a[href^='tel:']", false
    assert_select "a[href*='google.com/maps']", false
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bin/rails test test/integration/rider_orders_test.rb -n "/items as a list|call or navigate/"`
Expected: FAIL — `ul.rider-items` not found, `table.order-items` still present.

- [ ] **Step 3: Rewrite the rider show view**

Replace the entire contents of `app/views/rider/orders/show.html.erb` with:

```erb
<% content_for :title, "Entrega de #{@order.recipient_name}" %>

<div class="rider-detail">
  <%= link_to "← Mis entregas", rider_orders_path, class: "rider-detail__back" %>

  <% if @order.latitude && @order.longitude %>
    <div class="rider-detail__map order-map"
         data-controller="map"
         data-map-api-key-value="<%= ENV["MAPBOX_API_KEY"] %>"
         data-map-lat-value="<%= @order.latitude %>"
         data-map-lng-value="<%= @order.longitude %>"></div>
  <% end %>

  <header class="rider-detail__head">
    <h1 class="rider-detail__name"><%= @order.recipient_name %></h1>
    <span class="status-pill status-pill--<%= @order.status %>">
      <span class="status-pill__dot"></span>
      <%= Rider::OrdersController::STATUS_LABELS[@order.status] %>
    </span>
  </header>

  <p class="rider-detail__line"><i class="fa-solid fa-location-dot"></i> <%= @order.address %></p>
  <p class="rider-detail__line"><i class="fa-solid fa-phone"></i> <%= @order.recipient_phone %></p>

  <ul class="rider-items">
    <% @order.order_items.each do |item| %>
      <li class="rider-items__row">
        <span><%= item.quantity %>× <%= item.product.name %></span>
        <span class="rider-items__amount">$<%= number_with_delimiter(item.subtotal) %></span>
      </li>
    <% end %>
    <li class="rider-items__row rider-items__row--total">
      <span>Total</span>
      <span class="rider-items__amount">$<%= number_with_delimiter(@order.total) %></span>
    </li>
  </ul>

  <div class="rider-detail__actions">
    <% if @order.assigned? %>
      <%= button_to "Marcar en camino", rider_order_path(@order), method: :patch,
            params: { transition: "en_route" }, class: "btn btn-brand rider-detail__cta" %>
    <% elsif @order.en_route? %>
      <%= button_to "Marcar entregada", rider_order_path(@order), method: :patch,
            params: { transition: "delivered" }, class: "btn btn-brand rider-detail__cta" %>
    <% else %>
      <p class="empty-state">Entrega completada ✓</p>
    <% end %>
  </div>
</div>
```

(The map keeps the `order-map` class + `data-map-*` attributes, so the existing "show wires the order map element" test stays green; sizing is overridden under `.rider-shell` in the next step.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bin/rails test test/integration/rider_orders_test.rb -n "/items as a list|call or navigate/"`
Expected: PASS.

- [ ] **Step 5: Run the whole rider suite to confirm no regression**

Run: `bin/rails test test/integration/rider_orders_test.rb`
Expected: PASS (including the pre-existing "show wires the order map element" test).

- [ ] **Step 6: Add the detail styles (map protagonist, items list, sticky action)**

Append to `app/assets/stylesheets/pages/_rider.scss`:

```scss
// --- Order detail: map protagonist ---
.rider-detail {
  display: flex;
  flex-direction: column;

  &__back {
    font-size: 13px;
    color: $muted;
    text-decoration: none;
    margin-bottom: 12px;
  }
  &__head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    margin: 14px 0 4px;
  }
  &__name {
    margin: 0;
    font-family: $headers-font;
    font-size: 22px;
    font-weight: 800;
    letter-spacing: -0.5px;
  }
  &__line {
    color: $ink-2;
    margin: 6px 0;
    i { color: $muted; margin-right: 7px; }
  }
}

// Map breaks out of the main padding (full-bleed) and is tall on mobile.
.rider-shell .order-map {
  height: 42vh;
  min-height: 240px;
  margin: 0 -16px 4px;
  border: 0;
  border-bottom: 1px solid $line;
  border-radius: 0;
}

// Items list (replaces the <table>).
.rider-items {
  list-style: none;
  margin: 16px 0;
  padding: 0;

  &__row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    padding: 11px 0;
    border-bottom: 1px solid $line;
    color: $ink-2;
  }
  &__amount { font-weight: 600; white-space: nowrap; }
  &__row--total {
    border-bottom: 0;
    color: $ink;
    font-weight: 800;
    font-size: 16px;
  }
}

// Primary action fixed at the bottom (thumb reach), full width on mobile.
.rider-detail__actions {
  position: sticky;
  bottom: 0;
  margin: 8px -16px 0;
  padding: 12px 16px;
  padding-bottom: calc(12px + env(safe-area-inset-bottom));
  background: linear-gradient(180deg, rgba($bg, 0), $bg 38%);

  form { margin: 0; }
  .rider-detail__cta { width: 100%; padding: 15px; font-size: 15px; }
  .empty-state { text-align: center; padding: 14px 0; }
}

// --- Tablet / desktop: column layout, map inside the column, static action ---
@media (min-width: 768px) {
  .rider-shell .order-map {
    height: 340px;
    margin: 0 0 6px;
    border: 1px solid $line;
    border-radius: 16px;
  }
  .rider-detail__actions {
    position: static;
    margin: 18px 0 0;
    padding: 0;
    background: none;
    .rider-detail__cta { width: auto; }
  }
}
```

- [ ] **Step 7: Commit**

```bash
git add app/views/rider/orders/show.html.erb app/assets/stylesheets/pages/_rider.scss \
        test/integration/rider_orders_test.rb
git commit -m "$(cat <<'EOF'
feat(rider): map-protagonist order detail with sticky action and items list

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: E2E verification with Playwright (rider + manager regression)

CSS/responsive behavior isn't covered by Minitest — verify it live. This task has no code; it confirms the spec's acceptance criteria. Requires the app running (`bin/dev`) with `MAPBOX_API_KEY` set in `.env`, and seed data with an assigned/en_route order for a rider (`bin/rails db:seed:replant` if needed).

- [ ] **Step 1: Log in as a rider and open Mis entregas (mobile)**

Resize the Playwright browser to 375×812, navigate to the app, log in as a rider, go to `/rider/orders`.
Expected: a compact **top bar** (logo + avatar + Salir), full-width list of `.order-card`s, **no** 228px dark sidebar, no horizontal scroll.

- [ ] **Step 2: Open an order detail (mobile) and check map-protagonist + sticky action**

Click an active delivery.
Expected: the **map sits at the top, full-bleed and tall**; below it the name + status pill, address/phone (text, **no** Call/Navigate buttons), items as a list, and the **action button fixed at the bottom** of the viewport (visible without scrolling to it). Confirm the map actually renders (3D fly-in / branded pin). Take a screenshot of the `.rider-detail` element.

- [ ] **Step 3: Advance the order**

Tap "Marcar en camino" (or "Marcar entregada").
Expected: redirect to `/rider/orders` with the success flash; status updated.

- [ ] **Step 4: Check desktop rendering**

Resize to ~1280×800, reload `/rider/orders` and an order detail.
Expected: top bar still used (no sidebar); content centered in a narrow column; map inside the column with rounded corners; action button static (not sticky), normal width.

- [ ] **Step 5: Manager regression check**

Log out, log in as a **manager**, open `/manager/orders` and a `/manager/orders/:id`.
Expected: **unchanged** — dark 228px sidebar present, kanban board, order detail with the original `<table>` and map. No `.rider-topbar`. Compare against current `master` look if in doubt.

- [ ] **Step 6: Record the result**

Note pass/fail per criterion in the PR description (and attach the mobile detail screenshot). If anything fails, fix in Task 1/2 and re-verify before continuing.

---

## Task 4: Full CI and finish

- [ ] **Step 1: RuboCop**

Run: `bin/rubocop`
Expected: clean (no offenses). Fix any reported in the files you touched.

- [ ] **Step 2: Full test suite**

Run: `bin/rails test`
Expected: all green.

- [ ] **Step 3: Full CI pipeline (source of truth)**

Run: `bin/ci`
Expected: setup + RuboCop + security scanners + tests + seed replant all pass.

- [ ] **Step 4: Finish the branch**

Use the `superpowers:finishing-a-development-branch` skill to open the PR from `feature/rider-mobile-first` (per project workflow: spec + plan + PR). Include the spec/plan links, the acceptance-criteria results, and the mobile screenshot from Task 3.

---

## Self-Review Notes

- **Spec coverage:** top-bar nav → Task 1; map-protagonist detail → Task 2; items table→list → Task 2; no call/navigate → Task 2 (test) ; sticky bottom action → Task 2 (CSS); 768px breakpoint → Tasks 1–2 CSS; manager isolation → dedicated layout (Task 1) + regression test (Task 1 Step 7) + E2E (Task 3 Step 5); accessibility/reduced-motion → unchanged `map_controller.js`; verification (Minitest + RuboCop + Playwright + bin/ci) → Tasks 1–4. All covered.
- **No placeholders:** every code/test/CSS block is complete; commands have expected output.
- **Type/selector consistency:** `.rider-topbar`, `.rider-shell`, `.rider-shell__main`, `.rider-detail`, `.rider-detail__map`/`.order-map`, `.rider-detail__head`/`__name`/`__line`/`__actions`/`__cta`, `.rider-items`/`__row`/`__amount`/`--total` are used identically in views, CSS, and tests. The map div carries both `order-map` (test + base contract) and `rider-detail__map`.
