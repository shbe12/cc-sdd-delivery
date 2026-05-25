# Mapa de orden con look "pulido" (dusk + marcador de marca + fly-in)

**Fecha:** 2026-05-25
**Estado:** Aprobado (decisiones validadas con el usuario en brainstorming, con comparativas reales renderizadas vía Playwright)

## Problema

El mapa de las órdenes ya se renderiza en **3D con pitch** (estilo Standard,
`pitch: 60`, `bearing: -17`, ver `app/javascript/controllers/map_controller.js`),
pero se ve **plano y genérico**: usa la iluminación de día por defecto y el **pin azul
estándar de Mapbox**, que no refleja la identidad de PizzApp. El 3D está, pero no "luce".

Mapbox sí permite mejorar esto: el estilo **Standard** (mapbox-gl v3) expone propiedades
de configuración en vivo (`setConfigProperty`) para iluminación y tema, además de niebla
atmosférica (`setFog`), marcadores personalizados y animación de cámara. Queremos
aprovecharlas para que el mapa luzca cuidado, sin tocar nada del dominio.

## Objetivos

1. Aplicar el **"combo pulido"** validado con el usuario al mapa de orden:
   iluminación **`dusk`** + **niebla** atmosférica + **marcador de marca PizzApp** +
   **fly-in** de cámara al abrir.
2. Que el cambio cubra **ambas** pantallas de orden (manager y rider), que comparten el
   único controlador Stimulus `map`.
3. Mantener la app **accesible** (respetar `prefers-reduced-motion`) y la suite **verde**.

## No-objetivos

- **No** tocar modelo `Order`, controladores, vistas `show` ni `db/seeds.rb`. El geocoding
  a CDMX y las direcciones sobre Reforma ya quedaron resueltos en esta rama; las vistas ya
  cablean `lat`/`lng`/`api-key` al controlador. Este cambio es **solo presentación** (JS + SCSS).
- **No** cambiar el estilo base (sigue `mapbox://styles/mapbox/standard`) ni el `theme`
  (se mantiene `default`; el combo aprobado no usaba `faded`/`monochrome`).
- **No** introducir un runner/transpilador de JS. La app es importmap sin build; no se
  añaden unit tests de JS (requeriría tooling nuevo, fuera de alcance). El comportamiento
  se verifica con Playwright.
- **No** iluminación dinámica por hora del día: el usuario eligió **`dusk` fija** para que
  el mapa luzca dramático siempre y de forma determinista.
- **No** auto-rotación continua de cámara (descartada por distraer / consumir batería).

## Decisiones de diseño (validadas con el usuario)

- **Combo pulido** elegido sobre las otras opciones (day baseline, night, faded, monochrome),
  comparando capturas reales del corredor Reforma/Chapultepec renderizadas con Playwright.
- **Iluminación `dusk` fija** (no según hora local).
- **Fly-in al abrir, una sola vez** (no auto-rotación). Debe **respetar
  `prefers-reduced-motion`**: si el usuario lo prefiere, arrancar directo en la vista final.
- **Marcador de marca**: pin verde albahaca (`$brand`, `#16A34A`) con icono 🍕 y anillo que
  **pulsa**, en lugar del `Marker` azul por defecto.

## Solución

Dos archivos cambian; nada del dominio se toca.

### 1. Controlador de mapa — `app/javascript/controllers/map_controller.js`

Estado actual: construye el `Map` con la vista inclinada final y añade un `Marker` por
defecto. Cambios:

- **Cámara inicial "amplia" + fly-in.** Inicializar el mapa en una vista más alejada y
  plana (p. ej. `zoom ~13.5`, `pitch 0`, `bearing 0`, mismo `center`). En el evento `load`,
  animar a la vista final con
  `map.easeTo({ center, zoom: 15.5, pitch: 60, bearing: -17, duration: 2800, essential: true })`.
  - **Reduced-motion:** si `window.matchMedia('(prefers-reduced-motion: reduce)').matches`,
    inicializar **directamente** en la vista final (`zoom 15.5`, `pitch 60`, `bearing -17`)
    y **omitir** el `easeTo`.
- **Iluminación + niebla.** En el evento `style.load` (cuando el estilo Standard ya cargó):
  - `map.setConfigProperty('basemap', 'lightPreset', 'dusk')`
  - `map.setFog({ range: [1, 12], color: '#e6eef8', 'high-color': '#9ec1ec', 'horizon-blend': 0.25, 'space-color': '#0c1330', 'star-intensity': 0.05 })`
- **Marcador de marca.** En vez de `new mapboxgl.Marker()`, construir un elemento DOM
  (`<div class="order-pin"><span class="order-pin__pulse"></span><span class="order-pin__dot">🍕</span></div>`)
  y pasarlo a `new mapboxgl.Marker({ element, anchor: 'bottom' }).setLngLat([lng, lat])`,
  ajustando el CSS para que la punta del pin caiga sobre la coordenada.
- **Se conservan:** el guard `if (!this.apiKeyValue) return`, los `values`
  (`apiKey`/`lat`/`lng`) y `disconnect() { this.map?.remove() }`.

### 2. Estilos del marcador — `app/assets/stylesheets/components/_order-map-marker.scss` (nuevo)

- Importado desde `app/assets/stylesheets/components/_index.scss`.
- Define el pin (forma de gota, gradiente verde sobre `$brand`, sombra, icono 🍕 centrado)
  y el anillo con `@keyframes` de pulso.
- Usa el token `$brand` (`config/_colors.scss`) para mantener la identidad.

## Flujo

- **Ver orden** (`manager#show` / `rider#show`) → la vista pasa `lat`/`lng`/`api-key` al
  controlador Stimulus `map` → el mapa carga el estilo Standard, aplica `lightPreset: dusk`
  + niebla, coloca el marcador PizzApp sobre el destino y hace el **fly-in** a la vista
  inclinada (o arranca directo si hay reduced-motion).
- Un único controlador cubre **manager y rider**.

## Criterios de aceptación (verificables)

Tras abrir una orden con coordenadas válidas y dejar asentar el fly-in:

1. `map.getPitch()` ≈ `60` y `map.getZoom()` ≈ `15.5` (vista final alcanzada).
2. `map.getConfigProperty('basemap', 'lightPreset') === 'dusk'`.
3. `map.getFog()` no es `null` (niebla aplicada).
4. Existe en el DOM del mapa un elemento `.order-pin` (marcador de marca) y **no** el pin
   SVG por defecto de Mapbox.
5. Con `prefers-reduced-motion: reduce` simulado, la vista final se alcanza **sin**
   animación (sin `easeTo`).
6. Aplica igual en `manager#show` y en `rider#show`.

## Testing / verificación

1. **Suite Minitest** (`bin/rails test`): se mantiene verde — no hay cambios Ruby.
   `bin/rubocop` limpio (el cambio es JS + SCSS).
2. **Test de cableado (vista/controlador):** asegurar/confirmar que `order#show` para
   manager y para rider renderiza el `.order-map` con sus `data-map-api-key-value`,
   `data-map-lat-value`, `data-map-lng-value`. Guarda contra romper el contrato vista↔JS.
3. **E2E con Playwright MCP** (la prueba real del comportamiento JS, ya que no hay runner de
   JS): login como manager y como rider, abrir una orden y, sobre la instancia viva
   (`window.Stimulus.getControllerForElementAndIdentifier(el, 'map').map`), comprobar los
   **criterios de aceptación 1–5**. Capturas **del elemento** `.order-map` (no `fullPage`),
   en estado de día (referencia) vs. el nuevo look, para confirmar visualmente el pin de
   marca y la atmósfera.

## Riesgos / consideraciones

- **Timing de `setConfigProperty`/`setFog`:** deben ejecutarse tras `style.load`; hacerlo
  antes lanza error o se ignora. El fly-in (`easeTo`) va en `load`.
- **Ancla del marcador:** el elemento custom debe anclarse (`anchor: 'bottom'`) y diseñarse
  para que la punta del pin coincida con la coordenada, no su centro.
- **Animación del pulso** vía CSS `@keyframes`: ligera; no impacta rendimiento. El pulso es
  decorativo, no transmite estado de la orden.
- **Sin `MAPBOX_API_KEY`** el guard ya evita inicializar el mapa (comportamiento
  preexistente); la verificación E2E requiere la key en `.env` (dev).
- El cambio es puramente visual: si Mapbox cambiara nombres de propiedades del estilo
  Standard en una versión futura, el mapa seguiría cargando (el `setConfigProperty` fallaría
  de forma aislada), pero la versión está fijada a `mapbox-gl@3.7.0` en `config/importmap.rb`.
