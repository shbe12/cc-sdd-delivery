# Experiencia del rider mobile-first (barra superior + detalle con mapa protagonista)

**Fecha:** 2026-05-25
**Estado:** Aprobado en brainstorming (decisiones validadas con el usuario, con mockups renderizados vía companion visual). Pendiente revisión del spec por el usuario.

## Problema

El rider trabaja **con el teléfono en la mano y en movimiento**, pero hoy la app no es
mobile-first para él:

- El **shell es compartido** (`app/views/layouts/application.html.erb` → `shared/_sidebar`
  + `components/_app_shell.scss`) con un **sidebar oscuro fijo de 228px** y **sin ningún
  `@media`**. En un teléfono ese sidebar aplasta/empuja el contenido.
- La **pantalla de detalle de entrega** (`rider/orders/show`) apila datos, mapa, una
  **`<table>` de items** y el botón de acción en un flujo pensado para escritorio. La tabla
  no colapsa bien y el botón principal queda lejos del pulgar.

El rider solo tiene **una sección** ("Mis entregas"), así que el chrome de navegación puede
ser mínimo. Queremos una experiencia limpia, mobile-first, **sin tocar al manager**.

## Objetivos

1. **Navegación del rider = barra superior** (opción A validada): header compacto
   (logo → home del rol + avatar/Salir), contenido a pantalla completa. Mobile-first que
   escala bien a escritorio.
2. **Detalle de entrega = mapa protagonista** (opción B validada): el **mapa grande arriba
   a sangre**, debajo nombre + status, dirección/teléfono (texto) e items, y el **botón de
   acción fijo abajo, al alcance del pulgar** en móvil.
3. **Aislamiento total**: cero cambios de comportamiento o apariencia para el **manager**.
4. Mantener accesibilidad (el mapa ya respeta `prefers-reduced-motion`) y la suite **verde**.

## No-objetivos

- **NO** tocar al manager. Ni sus vistas, ni su controlador, ni su apariencia. **Restricción
  dura del usuario.** Garantía técnica: ver "Aislamiento" abajo.
- **NO** modificar archivos compartidos del shell: `application.html.erb`, `shared/_sidebar`,
  `components/_app_shell.scss`, ni los estilos compartidos de `pages/_orders.scss` (que
  `manager/show` también usa: `.order-detail`, `.order-map`, `.order-items`…).
- **NO** botones de **Llamar** ni **Navegar** (descartados por el usuario). El teléfono y la
  dirección se quedan como **texto**, igual que hoy.
- **NO** Turbo Streams / tracking en vivo: es una feature aparte, fuera de este pase responsive.
- **NO** rediseñar la lógica de órdenes ni el `map_controller.js` (el mapa 3D pulido se reusa
  tal cual; solo cambia su tamaño/posición vía CSS).
- **NO** introducir runner/transpilador de JS (app importmap sin build). El comportamiento se
  verifica con Playwright.

## Decisiones de diseño (validadas con el usuario)

- **Navegación: A · Barra superior**, entregada mediante un **layout propio del rider**
  (`layout "rider"`). Se eligió sobre la barra inferior (B) y el cajón hamburguesa (C): el
  rider tiene una sola sección, así que esas opciones añaden chrome sin aportar navegación.
- **Aislamiento: layout propio del rider** (elegido sobre "clase CSS solo-rider"). Los
  archivos compartidos quedan **100% intactos**.
- **La barra superior aplica en todos los tamaños** para el rider (mobile-first que escala),
  no solo en móvil. El rider deja de ver el sidebar; en escritorio el contenido se centra en
  una columna angosta. *(Cambio notable también en escritorio del rider — confirmar en la
  revisión del spec.)*
- **Detalle: B · Mapa protagonista**, **sin** Llamar/Navegar. Acción principal
  (*Marcar en camino* / *Marcar entregada*) **fija abajo** en móvil.
- **Items: `<table>` → lista** (`<ul>`) para que lea bien en móvil sin romperse.
- **Breakpoint: 768px** (Bootstrap `md`). Mobile-first: estilos base para móvil, mejoras a
  partir de `min-width: 768px`.

## Aislamiento (cómo se garantiza "cero impacto al manager")

1. **Layout exclusivo del rider.** `Rider::BaseController` declara `layout "rider"`, así que
   **todas** las vistas del namespace `rider` usan `app/views/layouts/rider.html.erb`. El
   manager sigue usando `application.html.erb` **sin cambios**.
2. **CSS namespaced bajo `.rider-shell`.** Todo estilo nuevo del rider vive bajo el contenedor
   `.rider-shell` (que solo existe en el layout del rider) o bajo clases nuevas con prefijo
   `rider-*`. El manager no tiene `.rider-shell` → su render es **byte-idéntico**.
3. **El detalle del rider usa markup/clases propias** (`rider-detail*`, `rider-items*`), no
   las clases compartidas que `manager/show` reutiliza. No se edita `pages/_orders.scss`.
4. **Único toque a un archivo compartido:** una línea `@import "rider";` en
   `pages/_index.scss` para que el SCSS nuevo compile. Es **aditivo** y los selectores están
   namespaced, así que el manager no se ve afectado. (El `<head>` se **duplica** en el layout
   del rider para no tocar `application.html.erb`; ver Riesgos.)

## Solución

Archivos del rider (+1 import compartido aditivo). Nada del dominio ni del manager se toca.

### 1. `app/controllers/rider/base_controller.rb`
- Añadir `layout "rider"` para que todo el namespace rider use el nuevo layout.

### 2. `app/views/layouts/rider.html.erb` (NUEVO)
- Documento HTML completo (duplica el `<head>` de `application.html.erb`: viewport, iconos,
  CSS de Mapbox, `stylesheet_link_tag`, `javascript_importmap_tags`) para **no** tocar el
  layout compartido.
- `<body>` con barra superior cuando hay sesión:
  - `header.rider-topbar`: marca (logo 🍕 + "PizzApp") enlazando a `rider_orders_path`, y a la
    derecha avatar (iniciales del email) + enlace **Salir** (`destroy_user_session_path`,
    `turbo_method: :delete`).
  - `main.rider-shell__main` que renderiza `shared/flashes` (partial compartido, solo lectura)
    y `yield`.
  - Todo envuelto en `.rider-shell` (el hook de namespacing CSS).

### 3. `app/views/rider/orders/show.html.erb` (reescritura, map-protagonist)
Estructura nueva, con clases propias del rider:
- Enlace de regreso `← Mis entregas` (`rider-detail__back`).
- **Mapa arriba, grande y a sangre** (`rider-detail__map`) reusando el contrato actual del
  controlador Stimulus `map` (mismos `data-map-*`: api-key, lat, lng). Render condicional si
  hay `latitude`/`longitude`.
- `header.rider-detail__head`: nombre del destinatario + `status-pill` (badge compartido, solo
  lectura).
- Líneas de teléfono y dirección como **texto** (iconos 📞/📍), **sin** botones.
- **Items como lista** `ul.rider-items` (fila: `cantidad× producto` · `$subtotal`) + fila
  final de **Total**. Sustituye la `<table class="order-items">`.
- `div.rider-detail__actions` con el `button_to` de acción (igual lógica que hoy:
  `assigned` → "Marcar en camino"; `en_route` → "Marcar entregada"; si no, "Entrega
  completada ✓"). En móvil se vuelve **fijo abajo**.

### 4. `app/views/rider/orders/index.html.erb` (ajustes mínimos)
- Funciona bien bajo el nuevo layout de ancho completo. Solo ajustar contenedor/espaciado si
  hace falta para móvil. El partial `_card` se mantiene (sus clases ya son flex y se afinan,
  si acaso, vía `.rider-shell`).

### 5. `app/assets/stylesheets/pages/_rider.scss` (NUEVO)
Todo el CSS del rider, mobile-first, namespaced:
- `.rider-topbar` / `.rider-shell` / `.rider-shell__main`: barra superior compacta y columna
  de contenido (angosta y centrada desde `min-width: 768px`).
- `.rider-detail`, `.rider-detail__map` (mapa alto y a sangre en móvil, p. ej. ~`40vh`;
  contenido respira), `.rider-detail__head`, `.rider-detail__line`.
- `.rider-items`, `.rider-items__row`, `.rider-items__row--total` (lista legible).
- `.rider-detail__actions`: en móvil `position: sticky; bottom: 0` ancho completo (pulgar);
  en escritorio, flujo normal.
- Reusa tokens (`$brand`, `$ink-2`, `$muted`, `$line`, `$headers-font`) y el botón `.btn-brand`.

### 6. `app/assets/stylesheets/pages/_index.scss` (1 línea aditiva)
- Añadir `@import "rider";`.

## Flujo

- **Rider inicia sesión** → `Rider::BaseController` (gate `require_rider`) → layout `rider`
  con **barra superior**.
- **Mis entregas** (`rider#index`): lista de tarjetas a ancho completo.
- **Ver entrega** (`rider#show`): **mapa protagonista** arriba (fly-in 3D existente) → datos e
  items → **botón de acción fijo abajo** (móvil). Avanzar estado funciona igual que hoy.
- **Manager**: sin cambios — sigue con `application.html.erb`, sidebar y kanban intactos.

## Criterios de aceptación (verificables)

1. Logueado como **rider**, en `/rider/orders` y `/rider/orders/:id` se ve la **barra
   superior** (`.rider-topbar`) y **no** el sidebar de 228px.
2. En `rider#show` el **mapa** aparece **arriba** (antes del nombre/items) y ocupa el ancho;
   el botón de acción está **al final**, fijo abajo en viewport móvil (375px).
3. Los items se renderizan como **lista** (`.rider-items`), no como `<table>`.
4. **No** existen botones de Llamar/Navegar; teléfono y dirección son texto.
5. En **375px** (móvil) no hay overflow horizontal ni el sidebar oscuro; en **≥768px** el
   contenido se centra en columna angosta bajo la barra superior.
6. Logueado como **manager**, `/manager/orders` y `/manager/orders/:id` se ven **idénticos a
   antes** (sidebar + kanban + tabla): regresión visual nula.
7. El mapa conserva su comportamiento (fly-in/dusk/pin de marca; respeta reduced-motion).

## Testing / verificación

1. **Minitest** (`bin/rails test`): verde. Si hay tests de request del rider, ajustar
   aserciones de markup que cambien (tabla→lista); añadir, si aporta, un test que confirme que
   `rider#show` usa el layout `rider` y que `manager#show` sigue con `application`.
2. **RuboCop** (`bin/rubocop`) limpio.
3. **E2E con Playwright MCP** (verificación real de UI, por memoria del proyecto):
   - Login como **rider** → `rider#index` y `rider#show` en viewport **móvil (375×812)** y
     **escritorio (~1280)**. Comprobar criterios 1–5 y 7; capturas del estado móvil
     (barra superior, mapa protagonista, botón fijo).
   - Login como **manager** → `manager#index` y `manager#show`: confirmar criterio 6
     (sin regresión; comparar con el look actual).
4. **`bin/ci`** como fuente de verdad de "mergeable" antes de cerrar.

## Riesgos / consideraciones

- **Duplicación del `<head>`** en `rider.html.erb`: es el precio de dejar
  `application.html.erb` 100% intacto (decisión del usuario: aislamiento por layout). El head
  es pequeño y estático; si en el futuro se vuelve un problema, se podría extraer a
  `shared/_head` (implicaría tocar el layout compartido — fuera de alcance ahora).
- **Mapa a sangre vs. padding del main**: el contenedor del mapa debe romper el padding del
  `main` en móvil (margen negativo o ancho completo) sin provocar scroll horizontal.
- **Botón sticky** debe dejar espacio inferior para no tapar el último item; cuidar el
  *safe-area* en notch (`env(safe-area-inset-bottom)`).
- **Clases compartidas reutilizadas solo-lectura** (`status-pill`, `btn-brand`): no se
  modifican; si se afinan para el rider, se hace **bajo `.rider-shell`**.
- **`_card` del rider** usa clases `order-card*` que son del rider (la index del rider); no
  colisionan con el kanban del manager. Verificar en el E2E que la lista sigue bien.
