# Manager Kanban Realtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cuando un rider transicione una orden a `en_route` o `delivered`, el kanban del manager debe reflejar el cambio en tiempo real sin recargar.

**Architecture:** `Order` declara un `after_update_commit` con guard que sólo dispara cuando `status` cambia a `en_route` o `delivered`; ese callback llama `broadcast_refresh_later_to "manager_orders"`. El index del manager se suscribe con `turbo_stream_from` y habilita Turbo Morph en su `<head>` para que la actualización reconcilie tarjetas y contadores sin parpadeo.

**Tech Stack:** Rails 8.1, turbo-rails 2.0.23 (`broadcasts_refreshes` / `turbo_refreshes_with`), Solid Cable (Action Cable adapter), Solid Queue (ActiveJob backend), Minitest.

**Spec:** `docs/superpowers/specs/2026-05-27-manager-kanban-realtime-design.md`

---

### Task 1: Broadcast en transiciones del rider (TDD)

**Files:**
- Modify: `app/models/order.rb`
- Test: `test/models/order_test.rb`

- [ ] **Step 1.1: Agregar `ActiveJob::TestHelper` y primer test (failing) para `mark_en_route!`**

`Turbo::Streams::BroadcastStreamJob` es el job que `broadcast_refresh_later_to` encola en turbo-rails 2.0. Lo aserto explícitamente. `ActiveJob::TestHelper` no está incluido por defecto en `ActiveSupport::TestCase`, hay que añadirlo.

En `test/models/order_test.rb`, justo después de `class OrderTest < ActiveSupport::TestCase`, añadir el `include`. Y al final, antes del `private`, añadir el primer test:

```ruby
class OrderTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  # ... (tests existentes intactos)

  test "mark_en_route! encola un broadcast refresh al canal manager_orders" do
    rider = User.create!(email: "broadcast1@example.com", password: "password123", role: :rider)
    order = create_order
    order.assign_to!(rider)

    assert_enqueued_with(job: Turbo::Streams::BroadcastStreamJob) do
      assert order.mark_en_route!
    end
  end

  # ... (private create_order existente)
end
```

- [ ] **Step 1.2: Correr el test para verificar que falla**

```bash
bin/rails test test/models/order_test.rb -n test_mark_en_route\!_encola_un_broadcast_refresh_al_canal_manager_orders
```

Expected: FAIL con `No enqueued job found with {:job=>Turbo::Streams::BroadcastStreamJob}` (no jobs encolados aún porque el callback no existe).

- [ ] **Step 1.3: Implementar el callback con guard en `Order`**

Editar `app/models/order.rb`. Justo después del `validate :must_have_at_least_one_item` y antes del bloque `def total`, añadir el callback. Luego, en la sección `private` (donde ya vive `must_have_at_least_one_item`), añadir los dos helpers privados:

```ruby
# en la sección pública, junto a los otros after_*/validate
after_update_commit :broadcast_rider_transition, if: :rider_transition?

# en la sección private, debajo de must_have_at_least_one_item
def rider_transition?
  saved_change_to_status? && %w[en_route delivered].include?(status)
end

def broadcast_rider_transition
  broadcast_refresh_later_to "manager_orders"
end
```

- [ ] **Step 1.4: Correr el test para verificar que pasa**

```bash
bin/rails test test/models/order_test.rb -n test_mark_en_route\!_encola_un_broadcast_refresh_al_canal_manager_orders
```

Expected: PASS (1 runs, 1 assertions, 0 failures).

- [ ] **Step 1.5: Añadir los tres tests restantes**

En el mismo `test/models/order_test.rb`, junto al test recién añadido:

```ruby
test "mark_delivered! encola un broadcast refresh al canal manager_orders" do
  rider = User.create!(email: "broadcast2@example.com", password: "password123", role: :rider)
  order = create_order
  order.assign_to!(rider)
  order.mark_en_route!

  assert_enqueued_with(job: Turbo::Streams::BroadcastStreamJob) do
    assert order.mark_delivered!
  end
end

test "assign_to! no encola broadcast (no es una transición del rider)" do
  rider = User.create!(email: "broadcast3@example.com", password: "password123", role: :rider)
  order = create_order

  assert_no_enqueued_jobs(only: Turbo::Streams::BroadcastStreamJob) do
    assert order.assign_to!(rider)
  end
end

test "update sin cambio de status no encola broadcast" do
  order = create_order

  assert_no_enqueued_jobs(only: Turbo::Streams::BroadcastStreamJob) do
    order.update!(recipient_phone: "5599998888")
  end
end
```

- [ ] **Step 1.6: Correr toda la suite del modelo para verificar que todo pasa**

```bash
bin/rails test test/models/order_test.rb
```

Expected: PASS. Todos los tests previos siguen pasando + los 4 nuevos. `assign_to!` y un `update` sin status change no encolan `BroadcastStreamJob`.

- [ ] **Step 1.7: Commit**

```bash
git add app/models/order.rb test/models/order_test.rb
git commit -m "feat(realtime): broadcast manager kanban refresh on rider transitions

Order#after_update_commit con guard rider_transition? llama
broadcast_refresh_later_to \"manager_orders\" solo cuando status pasa
a en_route o delivered.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Suscribir el kanban del manager + habilitar Turbo Morph

**Files:**
- Modify: `app/views/manager/orders/index.html.erb`

- [ ] **Step 2.1: Añadir el meta de morph en `content_for :head` y la suscripción al canal**

El layout `app/views/layouts/application.html.erb` ya tiene `<%= yield :head %>`, así que `content_for :head` se inyecta solo en esta página. La suscripción va al inicio del template (fuera del `.board`, antes del header).

Editar `app/views/manager/orders/index.html.erb`. Después de la línea `<% content_for :title, "Tablero de órdenes" %>` y antes del `<div class="board">`, añadir:

```erb
<% content_for :title, "Tablero de órdenes" %>

<% content_for :head do %>
  <%= turbo_refreshes_with method: :morph, scroll: :preserve %>
<% end %>

<%= turbo_stream_from "manager_orders" %>

<div class="board">
  <%# ... resto intacto ... %>
</div>
```

No tocar nada más en el template — las columnas, cards y contadores se re-renderizan en el GET silencioso que Turbo Morph dispara, y se reconcilian automáticamente.

- [ ] **Step 2.2: Correr la suite completa para confirmar que ninguna view test rompió**

```bash
bin/rails test
```

Expected: PASS. La suite no debería estar tocando esta vista en assertions específicas; si lo hace, el orden del DOM cambia mínimamente (un `<turbo-cable-stream-source>` extra). Si algún test falla por contar elementos, actualizarlo para ignorar ese elemento.

- [ ] **Step 2.3: Smoke check manual (documentado, no automatizado)**

Verificación manual antes del commit final:
1. `bin/dev` para arrancar el server.
2. En una pestaña, login como manager y abrir `/manager/orders`.
3. En otra pestaña/incognito, login como rider y abrir una orden asignada en `/rider/orders/:id`.
4. Tocar "En camino" en rider → confirmar que la tarjeta cruza de columna en la pestaña del manager sin recargar.
5. Tocar "Entregada" en rider → confirmar que la tarjeta se mueve a la columna "Entregada" y el contador "órdenes activas" disminuye en 1.

Si el rider no tiene una orden asignada de antemano, crear una desde el manager y asignarla antes del paso 3.

- [ ] **Step 2.4: Commit**

```bash
git add app/views/manager/orders/index.html.erb
git commit -m "feat(realtime): suscribir kanban del manager a manager_orders con morph

content_for :head inyecta turbo_refreshes_with method: :morph solo en
esta página; turbo_stream_from suscribe al canal que Order broadcastea
en transiciones del rider.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Verificación end-to-end con `bin/ci`

**Files:** (ninguno — solo verificación)

- [ ] **Step 3.1: Correr `bin/ci`**

```bash
bin/ci
```

Expected: PASS en todas las fases (setup, RuboCop, bundler-audit, importmap audit, brakeman, test suite, db:seed:replant). `bin/ci` es la fuente de verdad de "mergeable" según `CLAUDE.md`.

- [ ] **Step 3.2: Si RuboCop señala alguna ofensa en el código nuevo, corregir y commitear**

Sólo si aplica. Las correcciones típicas de rubocop-rails-omakase son cosméticas (espacios, comillas). Aplicar `bin/rubocop -a` para auto-corrección, revisar el diff, y:

```bash
git add -u
git commit -m "style: rubocop autocorrect en realtime kanban

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

Si no hay ofensas, omitir este step.

---

## Self-review

**Spec coverage:**
- "Callback con guard en `Order`" → Task 1 (Steps 1.3, 1.5 cubren los 4 escenarios del guard).
- "Suscripción `turbo_stream_from` en el index" → Task 2 (Step 2.1).
- "Habilitar morph vía `turbo_refreshes_with`" → Task 2 (Step 2.1, en `content_for :head`).
- "Model test enqueue / no-enqueue" → Task 1 (Steps 1.1, 1.5 — cubre `mark_en_route!`, `mark_delivered!`, `assign_to!`, non-status update).
- "System test manual documentado" → Task 2 (Step 2.3).
- Riesgos del spec (autorización del canal, stampede): documentados como notas en el spec, no requieren tareas — son trade-offs aceptados.

**Type/symbol consistency:**
- Canal `"manager_orders"` idéntico en modelo (Step 1.3) y view (Step 2.1).
- Método `broadcast_refresh_later_to` es el que matchea con `turbo_refreshes_with method: :morph` (turbo-rails 2.0).
- Job `Turbo::Streams::BroadcastStreamJob` es el que encola `broadcast_refresh_later_to` en turbo-rails 2.0 — consistente en los 4 tests.

**Placeholder scan:** sin TBD, TODO, "implement later", "add error handling" genéricos, ni código incompleto.
