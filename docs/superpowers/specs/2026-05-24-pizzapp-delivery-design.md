# PizzApp — App de delivery de un solo restaurante

**Fecha:** 2026-05-24
**Estado:** Diseño aprobado — listo para plan de implementación

## Resumen

App interna de gestión de entregas para **un solo restaurante** (una pizzería). El
**manager** registra las órdenes, las asigna a un **rider** y sigue su avance hasta la
entrega en un **tablero kanban**. Cada **rider** inicia sesión, ve solo sus entregas
asignadas y marca él mismo cuándo sale ("en camino") y cuándo entrega ("entregada").

No es un Uber Eats multi-restaurante: no hay clientes que hagan pedidos online ni
catálogo de restaurantes. El alcance es el flujo operativo manager → rider.

## Objetivos

- El manager puede crear una orden con datos del destinatario, dirección y varios
  productos, y asignarla a un rider.
- El rider ve sus entregas y avanza el estado de cada una.
- El manager ve todas las órdenes organizadas por estado en un tablero kanban.
- Cada orden geocodifica su dirección y muestra la ubicación de entrega en un mapa.

## Fuera de alcance (MVP)

- **Tiempo real / Turbo Streams.** Por ahora todo es recarga normal de página. El stack
  (Action Cable + Solid Cable) queda para una iteración posterior.
- **Pedidos de clientes / autoservicio.** Las órdenes las crea el manager.
- **CRUD de productos.** El menú es fijo y se siembra con seeds.
- **Pagos, facturación, ratings, chat.**
- **Tracking GPS en vivo del rider.** El mapa muestra el destino de entrega, no la
  posición del rider.

## Roles y autenticación

- Se reutiliza el `User` de Devise existente. Se agrega `role` (enum
  `{ manager: 0, rider: 1 }`, default `rider`). Los managers se siembran/promueven.
- `ApplicationController` ya exige login global (`before_action :authenticate_user!`).
- Helpers de rol: `current_user.manager?` / `current_user.rider?` (del enum).
- Autorización **hecha a mano** (sin Pundit), mediante `before_action` por namespace y
  *scoping* de las consultas (no solo ocultar en la vista).
- Ruteo por rol tras login: el manager aterriza en su tablero kanban; el rider en
  "Mis entregas" (vía `after_sign_in_path_for` / redirección desde la raíz según `role`).

## Modelo de datos

### `User` (Devise, existente — se extiende)
- `role` — enum `{ manager: 0, rider: 1 }`, default `rider`.
- `has_many :assigned_orders, class_name: "Order", foreign_key: :rider_id`.

### `Product` (nuevo, sembrado, sin CRUD)
- `name` — string, requerido.
- `price` — decimal, requerido (precio base).
- `has_many :order_items`.

### `Order` (nuevo)
- `recipient_name` — string, requerido (a quién se entrega).
- `recipient_phone` — string, requerido.
- `address` — string, requerido (texto que escribe el manager; se geocodifica).
- `latitude`, `longitude` — float (generados por `geocoder` desde `address`).
- `status` — enum `{ pending: 0, assigned: 1, en_route: 2, delivered: 3 }`,
  default `pending`.
- `belongs_to :rider, class_name: "User", optional: true` (nulo hasta asignar).
- `has_many :order_items, dependent: :destroy`, con `accepts_nested_attributes_for`.
- Validaciones: presencia de `recipient_name`, `recipient_phone`, `address`; debe tener
  al menos un `order_item`.
- `total` — **método** que suma `unit_price * quantity` de sus ítems (sin columna
  persistida que pueda desincronizarse).
- `geocoded_by :address`; `after_validation :geocode, if: ->{ address_changed? }`.

### `OrderItem` (nuevo)
- `belongs_to :order`.
- `belongs_to :product`.
- `unit_price` — decimal (**snapshot** del precio al momento; se copia de
  `product.price` en `before_validation` si está en blanco).
- `quantity` — integer, requerido, `> 0`.
- `subtotal` — método `unit_price * quantity`.

## Ciclo de vida de la orden

```
pending ──(manager asigna rider)──> assigned ──(rider)──> en_route ──(rider)──> delivered
```

- `pending → assigned`: el manager asigna un rider.
- `assigned → en_route`: el rider marca "en camino".
- `en_route → delivered`: el rider marca "entregada".

Las transiciones se exponen como **métodos de modelo** que validan que el paso sea legal
(p. ej. `order.assign_to!(rider)`, `order.mark_en_route!`, `order.mark_delivered!`), en
vez de setear el enum crudo desde el controlador.

## Pantallas y controladores

Controladores **namespaced** por rol para mantener fronteras claras y cada controlador
pequeño y enfocado.

### `Manager::OrdersController` (solo `role: manager`)
- **`index`** → **tablero kanban**: 4 columnas (Pendiente · Asignada · En camino ·
  Entregada) con tarjetas; contador por columna. Ve **todas** las órdenes.
- **`new` / `create`** → formulario `simple_form` con datos del destinatario (nombre,
  teléfono, dirección) + **líneas de orden dinámicas** (elegir `Product` + cantidad). El
  `unit_price` se copia del producto. Usa `accepts_nested_attributes_for` + un controlador
  Stimulus para agregar/quitar líneas.
- **`show`** → detalle: ítems, total, **mapa del destino** y formulario para **asignar
  rider** (select entre riders) cuando está pendiente.
- **`update`** → asigna rider (`pending → assigned`).

### `Rider::OrdersController` (solo `role: rider`)
- **`index`** → "Mis entregas": solo órdenes asignadas a `current_user`
  (`current_user.assigned_orders`). Muestra las **activas** (`assigned` + `en_route`);
  las `delivered` salen de la lista activa (visibles en una sección/colapso "entregadas
  hoy" o simplemente fuera del índice activo).
- **`show`** → detalle + **mapa** para ubicar la dirección + botones **"Marcar en
  camino"** y **"Marcar entregada"**.
- **`update`** → avanza estado, solo sobre órdenes propias.

## Mapa y geocoding

- Gem **`geocoder`**: la `Order` geocodifica `address` a `latitude`/`longitude` al
  guardar (solo si cambió la dirección).
- **Mapbox GL JS** pineado por importmap + un controlador Stimulus `map` que lee las
  coordenadas vía `data-*` y dibuja un marcador.
- `MAPBOX_API_KEY` en `.env` (dev/test vía `dotenv-rails`).
- El mapa aparece en el **show de la orden** (lo ven manager y rider para ubicar la
  entrega).

## Sistema de diseño

Dirección visual aprobada (ver mockup de alta fidelidad del companion). Look premium:
layout de paneles flotantes, sombras en capas, radios grandes, microinteracciones.

**Color de marca:** verde albahaca `#16A34A`.

| Token        | Valor      |
|--------------|------------|
| Fondo        | `#EFEFF3`  |
| Panel        | `#FFFFFF`  |
| Tinta        | `#191B22`  |
| Tinta 2      | `#4B5160`  |
| Apagado      | `#8A8F9C`  |
| Línea/hairline | `#E7E7EE` |

**Colores de estado:**

| Estado     | Punto/acento | Fondo pill | Texto pill |
|------------|--------------|------------|------------|
| Pendiente  | `#D99A2B`    | `#FBF0D8`  | `#8A5B12`  |
| Asignada   | `#5B72E8`    | `#E9EBFB`  | `#3742A6`  |
| En camino  | `#F2683C`    | `#FCE7DD`  | `#B0441F`  |
| Entregada  | `#2FA968`    | `#DFF3E7`  | `#1A7546`  |

**Tipografía:** Plus Jakarta Sans (títulos, nombres, totales) + Inter (cuerpo).
**Forma/profundidad:** radios 18–22px; sombras en dos capas; *inset highlights* sutiles;
fondo con gradientes radiales muy tenues derivados del color de marca.

**Detalles del kanban:** tarjeta por orden con pill de estado (con anillo interior del
color del estado), tiempo relativo, nombre del destinatario, dirección con ícono de pin,
resumen de ítems con cantidades resaltadas (`2×`), avatar del rider redondeado y total en
negrita. Las pendientes muestran botón punteado "+ Asignar rider"; las entregadas van
atenuadas. Hover que eleva la tarjeta y tiñe el borde con el color del estado.

**Implementación de estilos:** los tokens van en `app/assets/stylesheets/config/`
(`_bootstrap_variables.scss` antes de importar Bootstrap, más `_colors.scss` /
`_fonts.scss`), y los estilos por componente/página en `components/` y `pages/`, cada uno
referenciado desde su `_index.scss`. Fuentes vía Google Fonts.

## Seeds

- 1 manager (`role: manager`) + 2–3 riders (`role: rider`).
- Productos de la pizzería: Margarita, Pepperoni, Hawaiana, Coca-Cola, Agua.
- Algunas órdenes de ejemplo repartidas por estado, con `order_items` y direcciones reales
  geocodificables.

## Testing (Minitest)

- **Modelos:**
  - `Order#total` suma correctamente los subtotales.
  - Transiciones de estado válidas avanzan; las inválidas se rechazan.
  - `OrderItem` toma el `unit_price` como snapshot de `product.price`.
  - Validaciones (presencia, `quantity > 0`, al menos un ítem).
  - Geocoding *stubbeado* (no se pega a la API en tests).
- **Integración:**
  - El manager puede crear y asignar órdenes.
  - El rider avanza solo sus órdenes y **no** puede ver/actuar sobre ajenas.
  - Redirecciones de autorización por rol (rider fuera de `Manager::`, etc.).
- **Criterio de "mergeable":** pasa `bin/ci` completo (RuboCop, bundler-audit, importmap
  audit, brakeman, suite de tests y `db:seed:replant`).

## Decisiones y razones

- **`User` con `role` (no modelos separados):** un solo modelo de autenticación, más
  simple con Devise; suficiente para dos roles.
- **`Product` sembrado sin CRUD:** menú fijo y chico → el manager elige de un desplegable
  (sin errores de tipeo, precio único) sin costo de mantener una pantalla de admin.
- **`unit_price` como snapshot en `OrderItem`:** las órdenes históricas conservan su
  precio aunque cambie el del producto.
- **`total` como método (no columna):** evita datos desincronizados; el volumen es chico.
- **Dirección + `geocoder` (no lat/lng a mano):** patrón clásico de Le Wagon, más
  amigable para el manager.
- **Sin tiempo real en el MVP:** reduce complejidad; Turbo Streams se agrega después sobre
  la misma base de modelos.
- **Controladores namespaced por rol:** fronteras claras, cada controlador pequeño y la
  autorización vive junto al *scoping* de datos.
