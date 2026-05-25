# Geocoding correcto en CDMX + mapa de orden en 3D — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que las órdenes geocodifiquen de forma fiable dentro de Ciudad de México (corredor de Paseo de la Reforma) y renderizar el mapa de la orden en 3D con inclinación.

**Architecture:** El arreglo del geocoding es de **configuración + datos**, no de lógica del modelo: se añade sesgo de Mapbox (`country`/`proximity`) a `geocoder.rb` y se usan direcciones completas e inequívocas en `db/seeds.rb`, de modo que el callback `after_validation :geocode` ya existente produzca coordenadas correctas (sin hardcodear). El 3D es un cambio aislado en el controlador Stimulus de mapa (estilo Standard de mapbox-gl v3 + pitch). El modelo `Order`, los controladores y las vistas no se tocan.

**Tech Stack:** Rails 8.1, gem `geocoder` (lookup Mapbox), `mapbox-gl@3.7.0` vía importmap, Stimulus, Minitest, Playwright MCP para verificación E2E.

**Spec:** `docs/superpowers/specs/2026-05-25-cdmx-geocoding-3d-map-design.md`
**Rama:** `fix/cdmx-geocoding-3d-map`

---

## File Structure

| Archivo | Acción | Responsabilidad |
|---|---|---|
| `config/initializers/geocoder.rb` | Modificar | Sesgar el lookup Mapbox hacia CDMX (`country`, `proximity`, `language`) |
| `db/seeds.rb` | Modificar | Direcciones de orden completas e inequívocas sobre Paseo de la Reforma |
| `app/javascript/controllers/map_controller.js` | Modificar | Estilo Standard + `pitch`/`bearing`/`zoom` para vista 3D |
| `docs/superpowers/specs/2026-05-25-cdmx-geocoding-3d-map-design.md` | Crear | Spec/diseño |
| `docs/superpowers/plans/2026-05-25-cdmx-geocoding-3d-map.md` | Crear | Este plan |

No se crean modelos, migraciones, controladores ni vistas. **Nota de testing:** en `test`,
`geocoder.rb` usa `lookup: :test` con un stub fijo de CDMX, así que el geocoding **no es
unit-testeable** y el mapa es JS sin cobertura de unidad. La red de seguridad real es el
re-seed contra la API y la verificación E2E con Playwright (Task 4). Los tests de modelo
existentes (`test/models/order_test.rb`, incl. "geocodes the address on save") deben
seguir verdes sin cambios.

---

## Task 1: Sesgar el geocoding de Mapbox a CDMX

**Files:**
- Modify: `config/initializers/geocoder.rb`

- [x] **Step 1: Añadir `params` de sesgo a la config de Mapbox**

En la rama no-test de `Geocoder.configure(lookup: :mapbox, ...)`, añadir:

```ruby
  Geocoder.configure(
    lookup: :mapbox,
    api_key: ENV["MAPBOX_API_KEY"],
    units: :km,
    timeout: 5,
    params: {
      country: "mx",                  # restrict results to Mexico
      proximity: "-99.1332,19.4326",  # lng,lat — bias ranking toward CDMX center
      language: "es"
    }
  )
```

- [x] **Step 2: Verificar que la suite sigue verde**

Run: `bin/rails test`
Expected: PASS (42 runs, 0 failures). La rama `test` de `geocoder.rb` no cambia, así que
los tests de modelo no se ven afectados.

---

## Task 2: Direcciones inequívocas sobre Paseo de la Reforma

**Files:**
- Modify: `db/seeds.rb`

- [x] **Step 1: Reemplazar las 5 direcciones del array `samples`**

```ruby
  # Addresses on the Paseo de la Reforma skyscraper corridor (Ángel ↔ Diana) for a striking 3D map.
  { name: "Ana Gómez",  phone: "5512345678", address: "Paseo de la Reforma 505, Cuauhtémoc, 06500 Ciudad de México, CDMX", # Torre Mayor
    status: :pending,  rider: nil,        items: [ [ :margarita, 1 ], [ :coca, 1 ] ] },
  { name: "Carla Ruiz", phone: "5512345679", address: "Paseo de la Reforma 483, Cuauhtémoc, 06500 Ciudad de México, CDMX", # Torre Reforma
    status: :pending,  rider: nil,        items: [ [ :pepperoni, 2 ], [ :agua, 1 ] ] },
  { name: "Beto Salas", phone: "5512345680", address: "Paseo de la Reforma 510, Cuauhtémoc, 06500 Ciudad de México, CDMX", # Torre BBVA
    status: :assigned, rider: riders[0],  items: [ [ :hawaiana, 1 ], [ :margarita, 1 ] ] },
  { name: "Luis Mora",  phone: "5512345681", address: "Paseo de la Reforma 509, Cuauhtémoc, 06500 Ciudad de México, CDMX", # Chapultepec Uno
    status: :en_route, rider: riders[0],  items: [ [ :pepperoni, 3 ], [ :coca, 1 ] ] },
  { name: "María Díaz", phone: "5512345682", address: "Av. Paseo de la Reforma 222, Juárez, 06600 Ciudad de México, CDMX", # Reforma 222
    status: :delivered, rider: riders[1], items: [ [ :hawaiana, 1 ], [ :agua, 1 ] ] }
```

El resto de la lógica de seeds no cambia; `order.save!` geocodifica con el sesgo nuevo.

- [x] **Step 2: Re-sembrar y confirmar coordenadas en CDMX**

Run:
```bash
bin/rails db:seed:replant
bin/rails runner 'Order.order(:id).find_each { |o| puts [o.address, o.latitude, o.longitude].inspect }'
```
Expected: las 5 órdenes con `latitude ≈ 19.42–19.43` y `longitude ≈ -99.16 a -99.18`
(Paseo de la Reforma). Si alguna resuelve raro, refinar el string de dirección — **nunca
hardcodear coordenadas**.

---

## Task 3: Mapa de orden en 3D con pitch

**Files:**
- Modify: `app/javascript/controllers/map_controller.js`

- [x] **Step 1: Usar el estilo Standard + pitch en el constructor de `Map`**

```js
    this.map = new mapboxgl.Map({
      container: this.element,
      style: "mapbox://styles/mapbox/standard", // 3D buildings + lighting (mapbox-gl v3)
      center: [this.lngValue, this.latValue],
      zoom: 15.5, // close enough for 3D buildings to render
      pitch: 60,  // strong tilt to show off the Reforma towers in 3D
      bearing: -17 // slight rotation for depth
    })
```

Se conservan el `Marker` y el guard `if (!this.apiKeyValue) return`. Manager y rider
comparten este controlador, así que ambas pantallas quedan en 3D.

- [x] **Step 2: Verificar que el asset servido contiene el código nuevo**

Run (con `bin/dev` levantado):
```bash
ASSET=$(curl -s http://localhost:3000/users/sign_in | grep -oE '/assets/controllers/map_controller[^"]*\.js' | head -1)
curl -s "http://localhost:3000${ASSET}" | grep -nE "standard|pitch|bearing"
```
Expected: aparecen `style: "mapbox://styles/mapbox/standard"`, `pitch: 60`, `bearing: -17`
(confirma que importmap sirve el archivo actualizado, no una versión cacheada).

---

## Task 4: Verificación end-to-end (tests + Playwright)

**Files:** ninguno (solo verificación)

- [x] **Step 1: Suite de tests + lint**

Run: `bin/rails test` → PASS (42 runs, 0 failures).
Run: `bin/rubocop` → sin offenses (la corrida canónica; `db/` y `config/` están excluidos
en `.rubocop.yml`).

- [x] **Step 2: E2E con Playwright MCP — manager**

Levantar `bin/dev`. Login como `manager@pizzapp.test` / `password123`, abrir una orden de
Reforma (p. ej. Torre BBVA) y, vía el snapshot/screenshot del elemento `.order-map`,
confirmar la vista 3D inclinada sobre la torre. Inspeccionar la instancia viva:

```js
const el = document.querySelector('[data-controller="map"]');
const m = window.Stimulus.getControllerForElementAndIdentifier(el, 'map').map;
({ pitch: Math.round(m.getPitch()), center: m.getCenter(), loaded: m.isStyleLoaded() });
```
Expected: `pitch: 60`, `center` en Reforma (lng ≈ -99.17, lat ≈ 19.42), `loaded: true`.
**Capturar el elemento** `.order-map`, no `fullPage` (el `fullPage` captura el canvas
WebGL plano).

- [x] **Step 3: E2E con Playwright MCP — rider**

Cerrar sesión, login como `pedro@pizzapp.test` / `password123`, abrir una entrega asignada
y repetir la verificación del Step 2 (mismo controlador compartido).

- [x] **Step 4: Limpieza**

Cerrar el navegador, borrar capturas temporales y detener el server (`bin/dev`).
