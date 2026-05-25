# Geocoding correcto en CDMX + mapa de orden en 3D

**Fecha:** 2026-05-25
**Estado:** Aprobado (decisiones validadas con el usuario en brainstorming)

## Problema

Los mapas de las órdenes se grafican en el lugar equivocado. El modelo `Order`
geocodifica la dirección en vivo con Mapbox (`config/initializers/geocoder.rb`, en
dev/prod usa `lookup: :mapbox`), pero el lookup **no tiene ningún sesgo de localidad**
y las direcciones de los seeds eran cortas/ambiguas (p. ej. `"Colima 143, Roma Norte,
CDMX"`). Sin nada que le diga a Mapbox que busque cerca de Ciudad de México, asocia
libremente: *Roma* → Roma (Italia), *Colima* → estado de Colima. Resultado: las órdenes
sembradas se dibujan en otro país/estado.

Los tests no lo detectan: en `test`, `geocoder.rb` usa `lookup: :test` con un stub que
siempre devuelve el centro de CDMX `[19.4326, -99.1332]`. El bug solo aparece contra la
API real (al sembrar, y cuando un manager crea una orden real).

Además, el mapa se mostraba **plano** (`mapbox://styles/mapbox/streets-v12`, sin pitch),
y se quería una vista en **3D con inclinación** que luciera la ciudad.

## Objetivos

1. Que **todas** las direcciones de orden geocodifiquen de forma fiable dentro de
   **Ciudad de México**, manteniendo la identidad mexicana de la app y **sin romper** la
   feature de geocoding (sin coordenadas hardcodeadas).
2. Renderizar el mapa de la orden en **3D con pitch** (vista inclinada + edificios 3D).
3. Aprovechar el 3D: sembrar las órdenes sobre el corredor de rascacielos de **Paseo de
   la Reforma**, donde los edificios altos hacen lucir la vista 3D.

## No-objetivos

- **No** hardcodear coordenadas en los seeds. El callback `after_validation :geocode`
  sobrescribiría cualquier `latitude`/`longitude` pasado a `Order.new`; evitarlo exigiría
  saltarse el callback, lo que vacía de sentido la feature de geocoding. El arreglo es de
  **configuración + datos**, no de lógica del modelo.
- **No** cambiar la ciudad a Nueva York (opción descartada por el usuario: rompe la
  identidad en español de la app).
- **No** tocar el modelo `Order`, los controladores ni las vistas (las vistas `show` ya
  cablean `lat`/`lng`/`api-key` al controlador de mapa).
- **No** tocar la rama `test` de `geocoder.rb` (el stub de CDMX se mantiene; los tests de
  modelo no se ven afectados).

## Decisiones de diseño (validadas con el usuario)

- **Mantener CDMX**, no Nueva York.
- **Geocoding en vivo, sin coordenadas hardcodeadas.** Se corrige la causa raíz con
  sesgo de Mapbox + direcciones inequívocas, y se verifica que las coordenadas generadas
  caigan en CDMX.
- **Direcciones sobre Paseo de la Reforma** (Ángel ↔ Diana) para lucir el 3D, con
  `pitch: 60`.

## Solución

### 1. Sesgo de geocoding a CDMX — `config/initializers/geocoder.rb`
En la rama no-test, añadir `params:` para sesgar cada petición a Ciudad de México:

```ruby
params: {
  country: "mx",                 # restringe resultados a México
  proximity: "-99.1332,19.4326", # lng,lat — sesga el ranking hacia el centro de CDMX
  language: "es"
}
```
- `proximity` va en formato **`longitud,latitud`** (convención Mapbox).
- `country: "mx"` restringe a México; `proximity` prioriza CDMX.
- Esto corrige **todo** el geocoding en vivo: seeds **y** órdenes creadas por managers.

### 2. Direcciones inequívocas sobre Reforma — `db/seeds.rb`
Las 5 órdenes apuntan a torres del corredor de Paseo de la Reforma, con dirección
completa (calle + número + colonia + alcaldía + CP + "Ciudad de México, CDMX"):

| Orden (estado) | Torre | Dirección |
|---|---|---|
| Ana Gómez (pending) | Torre Mayor | `Paseo de la Reforma 505, Cuauhtémoc, 06500 CDMX` |
| Carla Ruiz (pending) | Torre Reforma | `Paseo de la Reforma 483, Cuauhtémoc, 06500 CDMX` |
| Beto Salas (assigned) | Torre BBVA | `Paseo de la Reforma 510, Cuauhtémoc, 06500 CDMX` |
| Luis Mora (en_route) | Chapultepec Uno | `Paseo de la Reforma 509, Cuauhtémoc, 06500 CDMX` |
| María Díaz (delivered) | Reforma 222 | `Av. Paseo de la Reforma 222, Juárez, 06600 CDMX` |

El callback `order.save!` las geocodifica correctamente gracias al nuevo sesgo.

### 3. Mapa 3D / pitch — `app/javascript/controllers/map_controller.js`
`mapbox-gl@3.7.0` soporta el estilo moderno **Standard** con edificios 3D + iluminación
nativos. En el constructor de `Map`:

```js
style: "mapbox://styles/mapbox/standard", // edificios 3D + iluminación (v3)
zoom: 15.5,    // suficiente para que rendericen los edificios
pitch: 60,     // inclinación fuerte para lucir las torres en 3D
bearing: -17   // ligera rotación para dar profundidad
```
Se conserva el `Marker` y el guard de `apiKey`/lat/lng. Manager y rider comparten este
único controlador, así que el cambio cubre ambas pantallas.

## Flujo

- **Sembrar/crear orden** → `Order#save` → `after_validation :geocode` → Mapbox (ahora
  sesgado a CDMX) devuelve `latitude`/`longitude` dentro de CDMX.
- **Ver orden** (`manager`/`rider` `show`) → la vista pasa `lat`/`lng` al controlador
  Stimulus `map` → Mapbox renderiza el estilo Standard inclinado a 60° centrado en el
  destino, con el marcador encima.

## Testing / verificación

1. **Suite Minitest** (`bin/rails test`): se mantiene verde — el geocoder está stubbeado
   en test y el cambio de mapa es solo JS. `bin/rubocop` limpio (`db/` y `config/` están
   excluidos en `.rubocop.yml`).
2. **Re-seed + chequeo de coordenadas** (dev, Mapbox real vía `.env` `MAPBOX_API_KEY`):
   `bin/rails db:seed:replant` y luego un `bin/rails runner` que imprime
   `address/latitude/longitude` de cada orden y confirma que caen en CDMX/Reforma.
3. **End-to-end con Playwright MCP:** login como manager y como rider, abrir una orden, e
   inspeccionar la instancia viva del mapa
   (`window.Stimulus.getControllerForElementAndIdentifier(el, 'map').map`) — confirmar
   `getPitch() == 60`, centro en Reforma y estilo cargado. Capturas **del elemento**
   `.order-map` (no `fullPage`, que captura el canvas WebGL plano).

## Riesgos / consideraciones

- El geocoding en vivo depende de la calidad de Mapbox; con `country` + `proximity` +
  direcciones completas es fiable, pero la red de seguridad es la verificación del paso 2
  (si una dirección resuelve raro, se ajusta el string — nunca se hardcodea).
- Reforma es zona de oficinas/hoteles, menos "realista" para delivery de pizza que Roma
  Norte; es una decisión deliberada para lucir el 3D en la demo del taller.
- `bin/ci` ejecuta `db:seed:replant`; si corre sin `MAPBOX_API_KEY`, el geocoding falla
  de forma no fatal (lat/lng quedan nulos) — comportamiento preexistente, fuera de alcance.
