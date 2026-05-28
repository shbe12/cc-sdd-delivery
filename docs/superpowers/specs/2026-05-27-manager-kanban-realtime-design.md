# Manager kanban en tiempo real — diseño

## Problema

El tablero del manager (`Manager::OrdersController#index`) muestra las órdenes agrupadas en
columnas por status (pendiente, asignada, en camino, entregada), pero requiere recarga manual
para reflejar cambios. Cuando un rider marca una orden como `en_route` o `delivered` desde su
propia interfaz, el kanban del manager queda desactualizado hasta el próximo F5.

## Objetivo

Cuando un rider transicione una orden a `en_route` o `delivered`, la tarjeta de esa orden
debe moverse a la columna correcta en el kanban del manager en tiempo real, sin recarga.
Los contadores por columna y el contador de "órdenes activas" del header deben actualizarse
consistentemente.

## Alcance

**Dentro:**
- Transiciones disparadas por el rider: `pending → assigned` no aplica (la dispara el manager),
  pero `assigned → en_route` y `en_route → delivered` sí refrescan el kanban del manager.

**Fuera:**
- Manager creando órdenes (`#create`) o asignando un rider (`#update`) — no refrescan en vivo,
  el manager que dispara la acción ya ve el cambio vía redirect, y otros managers verán al
  recargar.
- Página de detalle del manager (`#show`) — sin actualización en vivo.
- Index del rider — sin actualización en vivo.

## Stack

- **turbo-rails 2.0.23** (ya pinned) con la macro `broadcasts_refreshes` y el helper
  `turbo_refreshes_with` para morph.
- **Solid Cable** como adaptador de Action Cable (configurado por defecto en Rails 8). No
  requiere Redis.
- **Solid Queue** para encolar el job de broadcast (`broadcast_refresh_later_to`).

## Diseño

### 1. Modelo `Order` — callback con guard

Se agrega un callback explícito que solo emite el refresh cuando la transición proviene del
rider:

```ruby
# app/models/order.rb
after_update_commit :broadcast_rider_transition, if: :rider_transition?

private

def rider_transition?
  saved_change_to_status? && %w[en_route delivered].include?(status)
end

def broadcast_rider_transition
  broadcast_refresh_later_to "manager_orders"
end
```

- `saved_change_to_status?` se evalúa después del commit, así que captura solo updates donde
  status realmente cambió.
- La lista blanca `%w[en_route delivered]` deja fuera la asignación (`pending → assigned`),
  que la dispara el manager.
- `broadcast_refresh_later_to` encola un `Turbo::Streams::BroadcastJob` que envía
  `<turbo-stream action="refresh">` al canal `"manager_orders"` desde Solid Queue, fuera del
  ciclo del request.

### 2. Vista del index — suscripción y morph

En `app/views/manager/orders/index.html.erb`:

```erb
<% content_for :head do %>
  <%= turbo_refreshes_with method: :morph, scroll: :preserve %>
<% end %>

<%= turbo_stream_from "manager_orders" %>
```

- `turbo_refreshes_with` inyecta los meta `turbo-refresh-method=morph` y
  `turbo-refresh-scroll=preserve` solo en esta página, vía el `yield :head` que ya existe en
  `application.html.erb`. El resto del sitio no cambia comportamiento.
- `turbo_stream_from "manager_orders"` suscribe al cliente al canal Action Cable.

### 3. Flujo end-to-end

1. Rider toca "En camino" en `rider/orders/show` → `Rider::OrdersController#update` →
   `order.mark_en_route!` → `update(status: :en_route)`.
2. Al commit, dispara `after_update_commit` → `rider_transition?` retorna true →
   `broadcast_refresh_later_to "manager_orders"` encola el job.
3. Solid Queue corre el job → emite `<turbo-stream action="refresh">` al canal.
4. Solid Cable entrega el stream a cada cliente suscrito (cada manager con el index abierto).
5. Cada cliente hace un GET silencioso a `/manager/orders`, recibe el HTML del kanban,
   y Turbo Morph reconcilia la diferencia: la tarjeta se mueve de columna, los contadores
   por columna se recalculan, y `@active_count` del header también — todo sin parpadeo y
   preservando scroll.

## Testing

### Model test (`test/models/order_test.rb`)

Verificar las dos caras del callback:

- `mark_en_route!` en una orden `assigned` encola un `Turbo::Streams::BroadcastJob` con
  stream `"manager_orders"`.
- `mark_delivered!` en una orden `en_route` encola el mismo job.
- `assign_to!` (transición `pending → assigned`) **no** encola el job.
- Un update no relacionado con status (ej. cambiar `recipient_phone`) **no** encola el job.

Usar `assert_enqueued_with(job: Turbo::Streams::BroadcastStreamJob)` y
`assert_no_enqueued_jobs(only: Turbo::Streams::BroadcastStreamJob)` con el adapter de test
estándar (`broadcast_refresh_later_to` encola `BroadcastStreamJob` en turbo-rails 2.0).

### System test (opcional)

No se incluye en CI por defecto (los system tests no corren en `bin/ci`). Se documenta como
verificación manual: abrir dos pestañas (manager y rider), avanzar el estado en rider,
confirmar que la tarjeta se mueve en el manager sin recargar.

## Riesgos y consideraciones

- **Autorización del stream**: `"manager_orders"` es un nombre de canal global sin firma.
  Cualquier usuario autenticado (incluido un rider) que conozca el nombre podría suscribirse
  vía DevTools. Para esta app de taller el riesgo es aceptable porque el contenido del kanban
  no es sensible más allá del rol manager. Mejora futura: usar `turbo_stream_from current_user,
  :manager_orders` o un stream firmado por rol.
- **Stampede de GETs**: cada transición dispara un GET al index por cada manager conectado.
  Para el tamaño esperado (≤ pocos managers) es aceptable. Si crece, considerar
  `broadcasts_to` con streams targetados en lugar de morph refresh.
- **Acoplamiento modelo→canal**: el modelo `Order` conoce el nombre del canal del manager.
  Aceptable dado el alcance acotado; documentar para que si en el futuro el rider también
  se suscribe, se introduzca un segundo canal en lugar de reusar este.
