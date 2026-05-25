# Landing page pública + entrada a "Iniciar sesión"

**Fecha:** 2026-05-24
**Estado:** Aprobado (diseño visual validado en la companion de brainstorming)

## Problema

Hoy la app no tiene una cara pública usable:

- `app/views/pages/home.html.erb` sigue siendo el placeholder del scaffold (`<h1>Pages#home</h1>`).
- No hay ningún enlace o botón visible a **Iniciar sesión**: para entrar hay que conocer la URL `/users/sign_in` de memoria.

En cambio, **la lógica por rol ya está cableada y funciona**:

- `User` tiene `enum :role, { manager: 0, rider: 1 }`.
- `ApplicationController#after_sign_in_path_for` → `dashboard_path_for` redirige tras el login: manager → `manager_orders_path`, rider → `rider_orders_path`.
- `PagesController#home` ya hace `redirect_to dashboard_path_for(current_user) if user_signed_in?`.
- El layout (`application.html.erb`) ya renderiza el contenido sin el app-shell cuando el usuario no está autenticado.

Por tanto, esta feature es **puramente la cara pública**: una landing tipo marketing para visitantes no autenticados, con puntos de entrada claros a iniciar sesión. La redirección por rol no se toca.

## Objetivos

1. Sustituir el placeholder de `home` por una **landing tipo marketing** en español, a tono con la marca (verde albahaca `#16A34A`, fuentes Inter / Plus Jakarta Sans, iconos Font Awesome).
2. Ofrecer botones de **Iniciar sesión** visibles (nav, hero y CTA final) que llevan a la pantalla de login de Devise.
3. **No exponer registro** en ningún punto de la cara pública (ni en la landing ni en la página de login).
4. Mantener intacta la redirección por rol de los usuarios ya autenticados.

## No-objetivos

- **No** añadir registro self-service ni un flujo de alta de cuentas. Las cuentas existen vía seed.
- **No** eliminar la capacidad `:registerable` de Devise (la edición de cuenta `registrations#edit` sigue disponible); solo se deja de **mostrar** el enlace "Sign up". Endurecer la ruta `/users/sign_up` queda como opción futura, no parte de este trabajo.
- **No** crear modelos, migraciones ni controladores nuevos.
- **No** modificar los dashboards de manager/rider ni el sidebar (incluida la unificación del logo 🍕 emoji vs `fa-pizza-slice`).

## Diseño de la página (aprobado)

Una sola página con **5 bloques**, copy en español, iconos Font Awesome en verde de marca, solo login.

1. **Nav** (sticky)
   - Izquierda: logo `fa-pizza-slice` + "PizzApp".
   - Derecha: enlace ancla "Características" (#caracteristicas) + botón **Iniciar sesión**.

2. **Hero dividido**
   - Columna izquierda: eyebrow "Gestión de pedidos y reparto"; titular **"Del horno a la puerta, en tiempo real."**; subtítulo describiendo que managers crean/asignan y repartidores entregan/actualizan, todo en vivo; botón **Iniciar sesión** + nota "Para managers y repartidores".
   - Columna derecha: mini-mockup del **tablero kanban** con las 4 columnas de estado usando los colores reales (Pendiente `#D99A2B`, Asignada `#5B72E8`, En ruta `#F2683C`, Entregada `#2FA968`).

3. **Características** (fondo `#EFEFF3`, 3 tarjetas)
   - Título "Todo lo que necesita tu operación" + subtítulo "Construido sobre Hotwire — sin recargas, sin sondeos."
   - Tarjeta 1 — `fa-bolt` "En tiempo real": cambios de estado al instante vía Turbo Streams.
   - Tarjeta 2 — `fa-table-columns` "Tablero kanban": órdenes por columna (pendiente, asignada, en ruta, entregada).
   - Tarjeta 3 — `fa-map-location-dot` "Reparto en mapa": destino en mapa Mapbox y avance paso a paso.

4. **Capturas** ("Míralo en acción")
   - Dos marcos placeholder estilizados (tablero kanban y mapa de reparto). Esta entrega los deja como placeholders; sustituirlos por capturas reales es un follow-up.

5. **CTA final + Footer**
   - Banda verde de marca: "¿Listo para empezar?" + botón **Iniciar sesión**.
   - Footer: logo "PizzApp" + "© 2026 PizzApp".

El mockup aprobado vive en `.superpowers/brainstorm/.../content/landing-full-v3.html` (no versionado).

## Flujo

- **Visitante no autenticado** → `GET /` → `PagesController#home` (sin redirección) → renderiza la landing.
- **Clic en "Iniciar sesión"** → `new_user_session_path` (`/users/sign_in`) → al enviar, Devise usa `after_sign_in_path_for` → dashboard según rol.
- **Usuario autenticado** → `GET /` → `redirect_to dashboard_path_for(current_user)` (comportamiento actual, sin cambios).

## Implementación

### Vista
- Reescribir `app/views/pages/home.html.erb` con el markup de los 5 bloques.
- Usar `link_to ..., new_user_session_path` en los tres CTAs de login.
- Enlace "Características" como ancla a la sección (`href="#caracteristicas"`).
- `content_for :title, "PizzApp — gestión de pedidos y reparto"`.
- Iconos decorativos con `aria-hidden="true"`; jerarquía de encabezados correcta (un único `h1` en el hero).

### Estilos
- Añadir los estilos de la landing en `app/assets/stylesheets/pages/_home.scss` (ya importado por `pages/_index.scss`).
- Reutilizar los design tokens de `config/_colors.scss` y las fuentes de `config/_fonts.scss`. No introducir nuevos colores fuera de la paleta existente.
- **Responsive:** el hero pasa de 2 columnas a apilado en móvil; las características de 3 columnas a apiladas; el nav reduce o esconde el enlace ancla en pantallas pequeñas.

### Sin registro en la cara pública
- Editar `app/views/devise/shared/_links.html.erb` para **no renderizar** el enlace "Sign up" (quitar el bloque `if devise_mapping.registerable?`), de modo que la página de login tampoco invite a registrarse.

### Coherencia de idioma en login (pulido menor)
- La vista `app/views/devise/sessions/new.html.erb` está en inglés ("Log in"). Traducir el encabezado y el botón a español ("Iniciar sesión") para que case con la landing y el resto del UI. Cambio mínimo, mismo archivo.

### Controlador
- `PagesController#home` no cambia (ya redirige a usuarios autenticados; ya hace `skip_before_action :authenticate_user!, only: [:home]`).

## Testing

- **Nuevo** test de integración para el caso no autenticado (p. ej. en `test/integration/role_routing_test.rb` o un `home_landing_test.rb`):
  - `GET root_path` sin sesión → `200 OK`.
  - La respuesta contiene un enlace a `new_user_session_path` y el copy clave del hero ("Iniciar sesión", "en tiempo real").
  - La respuesta **no** contiene un enlace a `new_user_registration_path` (no se expone registro).
- Los tests existentes de `role_routing_test.rb` (redirección de managers/riders autenticados) deben seguir en verde.
- Verde de extremo a extremo con `bin/ci` (RuboCop, scanners, suite de tests, `db:seed:replant`).

## Riesgos / consideraciones

- La ruta `/users/sign_up` seguirá existiendo aunque no se enlace; aceptable para el alcance actual (demo de workshop). Endurecerla es trabajo futuro.
- Los placeholders de "Capturas" no muestran producto real; si se desea, sustituir por capturas reales es un follow-up de bajo riesgo.
