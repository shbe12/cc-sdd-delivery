# Landing page pública + login — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reemplazar el placeholder de `pages#home` por una landing tipo marketing en español con entrada clara a "Iniciar sesión", y dejar la página de login en español sin exponer registro.

**Architecture:** Trabajo puramente de cara pública (vistas + estilos). La redirección por rol ya está implementada (`PagesController#home` + `ApplicationController#after_sign_in_path_for`) y no se toca. La landing se renderiza en la rama "no autenticado" del layout existente. Estilos en SCSS reutilizando los design tokens de la app. Se quita el enlace de registro del partial compartido de Devise.

**Tech Stack:** Rails 8.1, ERB, simple_form, Devise, SCSS (sassc-rails + sprockets), Font Awesome (`font-awesome-sass`, ya cargado), Minitest (integration tests con `Devise::Test::IntegrationHelpers`).

**Spec:** `docs/superpowers/specs/2026-05-24-landing-page-login-design.md`
**Rama:** `feat/landing-page-login`

---

## File Structure

| Archivo | Acción | Responsabilidad |
|---|---|---|
| `app/views/pages/home.html.erb` | Modificar (reemplazar) | Markup de la landing (nav, hero, características, capturas, CTA, footer) |
| `app/assets/stylesheets/pages/_home.scss` | Modificar | Estilos de la landing, usando los tokens de `config/_colors.scss` y `config/_fonts.scss` |
| `app/views/devise/sessions/new.html.erb` | Modificar | Página de login traducida al español |
| `app/views/devise/shared/_links.html.erb` | Modificar | Quitar enlace "Sign up"; traducir el resto de enlaces de auth |
| `test/integration/home_landing_test.rb` | Crear | Cubre la landing pública para invitados |
| `test/integration/login_page_test.rb` | Crear | Cubre el login en español y la ausencia de registro |

No se crean modelos, migraciones ni controladores. Los tests existentes en `test/integration/role_routing_test.rb` (redirección por rol de usuarios autenticados) deben seguir verdes sin cambios.

---

## Task 1: Landing pública (vista)

**Files:**
- Create: `test/integration/home_landing_test.rb`
- Modify: `app/views/pages/home.html.erb`

- [x] **Step 1: Escribir el test que falla**

Crear `test/integration/home_landing_test.rb`:

```ruby
require "test_helper"

class HomeLandingTest < ActionDispatch::IntegrationTest
  test "guests see the public landing" do
    get root_path

    assert_response :success
    assert_includes response.body, "Del horno a la puerta"
  end

  test "the landing offers a login entry point" do
    get root_path

    assert_response :success
    assert_select "a[href=?]", new_user_session_path, minimum: 1
  end

  test "the landing does not surface registration" do
    get root_path

    assert_response :success
    assert_select "a[href=?]", new_user_registration_path, count: 0
  end
end
```

- [x] **Step 2: Ejecutar el test y verificar que falla**

Run: `bin/rails test test/integration/home_landing_test.rb`
Expected: FAIL — los dos primeros tests fallan (el placeholder no contiene "Del horno a la puerta" ni un enlace a `new_user_session_path`).

- [x] **Step 3: Implementar la vista**

Reemplazar TODO el contenido de `app/views/pages/home.html.erb` por:

```erb
<% content_for :title, "PizzApp — gestión de pedidos y reparto" %>

<div class="landing">
  <%# ---- Nav ---- %>
  <header class="landing-nav">
    <span class="landing-nav__brand"><i class="fa-solid fa-pizza-slice" aria-hidden="true"></i> PizzApp</span>
    <nav class="landing-nav__links">
      <a href="#caracteristicas">Características</a>
      <%= link_to "Iniciar sesión", new_user_session_path, class: "landing-btn landing-btn--brand" %>
    </nav>
  </header>

  <%# ---- Hero ---- %>
  <section class="hero">
    <div class="hero__text">
      <p class="hero__eyebrow">Gestión de pedidos y reparto</p>
      <h1 class="hero__title">Del horno a la puerta,<br>en tiempo real.</h1>
      <p class="hero__lead">PizzApp coordina órdenes, cocina y reparto en un solo lugar. Los managers crean y asignan pedidos; los repartidores entregan y actualizan el estado — y todo se ve al instante en cada pantalla.</p>
      <div class="hero__cta">
        <%= link_to "Iniciar sesión", new_user_session_path, class: "landing-btn landing-btn--brand landing-btn--lg" %>
        <span class="hero__note">Para managers y repartidores</span>
      </div>
    </div>

    <div class="hero__preview">
      <div class="kanban-preview">
        <p class="kanban-preview__title">Tablero de órdenes</p>
        <div class="kanban-preview__cols">
          <div class="kanban-preview__col">
            <div class="kanban-preview__head"><span class="kanban-preview__dot kanban-preview__dot--pending"></span>Pendiente</div>
            <div class="kanban-preview__card"><span></span><span></span></div>
            <div class="kanban-preview__card"><span></span></div>
          </div>
          <div class="kanban-preview__col">
            <div class="kanban-preview__head"><span class="kanban-preview__dot kanban-preview__dot--assigned"></span>Asignada</div>
            <div class="kanban-preview__card"><span></span><span></span></div>
          </div>
          <div class="kanban-preview__col">
            <div class="kanban-preview__head"><span class="kanban-preview__dot kanban-preview__dot--en-route"></span>En ruta</div>
            <div class="kanban-preview__card"><span></span></div>
          </div>
          <div class="kanban-preview__col">
            <div class="kanban-preview__head"><span class="kanban-preview__dot kanban-preview__dot--delivered"></span>Entregada</div>
            <div class="kanban-preview__card"><span></span></div>
          </div>
        </div>
      </div>
    </div>
  </section>

  <%# ---- Características ---- %>
  <section class="features" id="caracteristicas">
    <h2 class="section-title">Todo lo que necesita tu operación</h2>
    <p class="section-sub">Construido sobre Hotwire — sin recargas, sin sondeos.</p>
    <div class="features__grid">
      <article class="feature-card">
        <div class="feature-card__icon"><i class="fa-solid fa-bolt" aria-hidden="true"></i></div>
        <h3>En tiempo real</h3>
        <p>Cada cambio de estado aparece al instante en el tablero del manager y en la pantalla del repartidor, vía Turbo Streams.</p>
      </article>
      <article class="feature-card">
        <div class="feature-card__icon"><i class="fa-solid fa-table-columns" aria-hidden="true"></i></div>
        <h3>Tablero kanban</h3>
        <p>Visualiza cada orden por columna: pendiente, asignada, en ruta y entregada. Toda la operación de un vistazo.</p>
      </article>
      <article class="feature-card">
        <div class="feature-card__icon"><i class="fa-solid fa-map-location-dot" aria-hidden="true"></i></div>
        <h3>Reparto en mapa</h3>
        <p>El repartidor ve el destino en un mapa Mapbox y avanza el estado paso a paso hasta la entrega.</p>
      </article>
    </div>
  </section>

  <%# ---- Capturas ---- %>
  <section class="shots">
    <h2 class="section-title">Míralo en acción</h2>
    <div class="shots__grid">
      <div class="shot"><i class="fa-solid fa-table-columns" aria-hidden="true"></i><span>Tablero kanban</span></div>
      <div class="shot"><i class="fa-solid fa-map-location-dot" aria-hidden="true"></i><span>Mapa de reparto</span></div>
    </div>
  </section>

  <%# ---- CTA final ---- %>
  <section class="landing-cta">
    <h2 class="landing-cta__title">¿Listo para empezar?</h2>
    <p class="landing-cta__sub">Inicia sesión con tu cuenta y entra directo a tu tablero.</p>
    <%= link_to "Iniciar sesión", new_user_session_path, class: "landing-btn landing-btn--on-brand landing-btn--lg" %>
  </section>

  <%# ---- Footer ---- %>
  <footer class="landing-footer">
    <span class="landing-footer__brand"><i class="fa-solid fa-pizza-slice" aria-hidden="true"></i> PizzApp</span>
    <span>© 2026 PizzApp</span>
  </footer>
</div>
```

- [x] **Step 4: Ejecutar el test y verificar que pasa**

Run: `bin/rails test test/integration/home_landing_test.rb`
Expected: PASS (3 runs, 0 failures).

- [x] **Step 5: Commit**

```bash
git add test/integration/home_landing_test.rb app/views/pages/home.html.erb
git commit -m "feat: public marketing landing for guests

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Estilos de la landing

**Files:**
- Modify: `app/assets/stylesheets/pages/_home.scss`

- [x] **Step 1: Implementar el SCSS**

Reemplazar TODO el contenido de `app/assets/stylesheets/pages/_home.scss` por (las variables `$brand`, `$bg`, `$panel`, `$ink`, `$ink-2`, `$muted`, `$line`, `$pending`, `$assigned`, `$en-route`, `$delivered`, `$headers-font` ya están definidas globalmente por `config/_colors.scss` y `config/_fonts.scss`, importados antes que este archivo):

```scss
// Specific CSS for your home-page — landing pública de PizzApp

.landing {
  background: $panel;

  .landing-btn {
    display: inline-block;
    padding: .5rem 1rem;
    border-radius: .5rem;
    font-weight: 600;
    font-size: .9rem;
    text-decoration: none;
    transition: opacity .15s ease;

    &--lg { padding: .7rem 1.4rem; font-size: 1rem; }
    &--brand { background: $brand; color: #fff; }
    &--on-brand { background: #fff; color: $brand; }
    &:hover { opacity: .9; }
  }
}

.landing-nav {
  position: sticky;
  top: 0;
  z-index: 10;
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: .9rem 1.6rem;
  background: $panel;
  border-bottom: 1px solid $line;

  &__brand {
    color: $brand;
    font-family: $headers-font;
    font-weight: 800;
    font-size: 1.15rem;
  }

  &__links {
    display: flex;
    align-items: center;
    gap: 1.2rem;

    a:not(.landing-btn) {
      color: $ink-2;
      text-decoration: none;
      font-size: .9rem;
    }
  }
}

.hero {
  display: flex;
  align-items: center;
  gap: 2rem;
  padding: 3rem 1.6rem;
  max-width: 1100px;
  margin: 0 auto;

  &__text { flex: 1; }

  &__eyebrow {
    color: $brand;
    font-weight: 700;
    font-size: .75rem;
    letter-spacing: .08em;
    text-transform: uppercase;
    margin: 0 0 .5rem;
  }

  &__title {
    font-family: $headers-font;
    font-weight: 800;
    font-size: 2.2rem;
    line-height: 1.15;
    color: $ink;
    margin: 0 0 .75rem;
  }

  &__lead {
    color: $ink-2;
    font-size: 1.05rem;
    line-height: 1.55;
    max-width: 36rem;
  }

  &__cta {
    display: flex;
    align-items: center;
    gap: .8rem;
    margin-top: 1.4rem;
  }

  &__note { color: $muted; font-size: .8rem; }

  &__preview { flex: 1; }
}

.kanban-preview {
  background: $panel;
  border: 1px solid $line;
  border-radius: .9rem;
  box-shadow: 0 12px 30px rgba($ink, .08);
  padding: .9rem;

  &__title {
    font-size: .7rem;
    font-weight: 700;
    color: $muted;
    text-transform: uppercase;
    letter-spacing: .04em;
    margin: 0 0 .6rem;
  }

  &__cols { display: flex; gap: .4rem; }

  &__col {
    flex: 1;
    background: $bg;
    border-radius: .5rem;
    padding: .4rem;
  }

  &__head {
    display: flex;
    align-items: center;
    gap: .25rem;
    font-size: .6rem;
    font-weight: 700;
    color: $ink-2;
    margin-bottom: .35rem;
  }

  &__dot {
    width: .45rem;
    height: .45rem;
    border-radius: 50%;

    &--pending   { background: $pending; }
    &--assigned  { background: $assigned; }
    &--en-route  { background: $en-route; }
    &--delivered { background: $delivered; }
  }

  &__card {
    background: $panel;
    border: 1px solid $line;
    border-radius: .35rem;
    padding: .4rem;
    margin-bottom: .35rem;

    span {
      display: block;
      height: .3rem;
      background: $line;
      border-radius: .2rem;

      & + span { margin-top: .25rem; width: 60%; }
    }
  }
}

.section-title {
  font-family: $headers-font;
  font-weight: 800;
  font-size: 1.5rem;
  text-align: center;
  color: $ink;
  margin: 0;
}

.section-sub {
  color: $muted;
  font-size: .9rem;
  text-align: center;
  margin: .3rem 0 0;
}

.features {
  background: $bg;
  padding: 3rem 1.6rem;

  &__grid {
    display: flex;
    gap: 1.2rem;
    max-width: 1000px;
    margin: 1.6rem auto 0;
  }
}

.feature-card {
  flex: 1;
  background: $panel;
  border: 1px solid $line;
  border-radius: .9rem;
  padding: 1.4rem;

  &__icon {
    width: 2.6rem;
    height: 2.6rem;
    border-radius: .6rem;
    background: rgba($brand, .1);
    color: $brand;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 1.1rem;
    margin-bottom: .8rem;
  }

  h3 { font-size: 1rem; margin: 0 0 .4rem; color: $ink; }
  p { color: $muted; font-size: .9rem; line-height: 1.5; margin: 0; }
}

.shots {
  padding: 3rem 1.6rem;
  max-width: 1000px;
  margin: 0 auto;

  &__grid {
    display: flex;
    gap: 1.2rem;
    margin-top: 1.6rem;
  }
}

.shot {
  flex: 1;
  height: 150px;
  background: $bg;
  border: 1px solid $line;
  border-radius: .9rem;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: .5rem;
  color: $muted;
  font-size: .85rem;

  i { font-size: 1.5rem; color: $line; }
}

.landing-cta {
  background: $brand;
  color: #fff;
  text-align: center;
  padding: 3.5rem 1.6rem;

  &__title {
    font-family: $headers-font;
    font-weight: 800;
    font-size: 1.6rem;
    margin: 0;
  }

  &__sub { opacity: .9; font-size: .95rem; margin: .5rem 0 1.2rem; }
}

.landing-footer {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 1.2rem 1.6rem;
  color: $muted;
  font-size: .8rem;

  &__brand { color: $muted; font-weight: 700; }
}

@media (max-width: 768px) {
  .hero { flex-direction: column; text-align: center; }
  .hero__lead { margin-left: auto; margin-right: auto; }
  .hero__cta { justify-content: center; flex-wrap: wrap; }
  .hero__preview { width: 100%; }
  .features__grid,
  .shots__grid { flex-direction: column; }
  .landing-nav__links a:not(.landing-btn) { display: none; }
}
```

- [x] **Step 2: Verificar que el SCSS compila**

Run: `bin/rails assets:precompile`
Expected: termina sin errores (sin `SassC::SyntaxError`). Los archivos generados van a `public/assets/`, que está en `.gitignore`.

- [x] **Step 3: Verificación visual (manual)**

Run: `bin/dev` y abrir `http://localhost:3000/` sin sesión.
Expected: se ve la landing con el hero dividido, el mini-tablero kanban con los colores de estado, las 3 tarjetas de características, las capturas, la banda verde de CTA y el footer. Detener con Ctrl-C.

- [x] **Step 4: Commit**

```bash
git add app/assets/stylesheets/pages/_home.scss
git commit -m "style: landing page styles using PizzApp tokens

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Login en español, sin registro

**Files:**
- Create: `test/integration/login_page_test.rb`
- Modify: `app/views/devise/sessions/new.html.erb`
- Modify: `app/views/devise/shared/_links.html.erb`

- [x] **Step 1: Escribir el test que falla**

Crear `test/integration/login_page_test.rb`:

```ruby
require "test_helper"

class LoginPageTest < ActionDispatch::IntegrationTest
  test "the login page heading is in Spanish" do
    get new_user_session_path

    assert_response :success
    assert_select "h2", text: "Iniciar sesión"
  end

  test "the login page does not link to registration" do
    get new_user_session_path

    assert_response :success
    assert_select "a[href=?]", new_user_registration_path, count: 0
  end
end
```

- [x] **Step 2: Ejecutar el test y verificar que falla**

Run: `bin/rails test test/integration/login_page_test.rb`
Expected: FAIL — el encabezado actual es "Log in" (no "Iniciar sesión") y el partial de Devise sí muestra un enlace "Sign up" a `new_user_registration_path`.

- [x] **Step 3: Traducir la página de login**

Reemplazar TODO el contenido de `app/views/devise/sessions/new.html.erb` por:

```erb
<h2>Iniciar sesión</h2>

<%= simple_form_for(resource, as: resource_name, url: session_path(resource_name)) do |f| %>
  <div class="form-inputs">
    <%= f.input :email,
                label: "Correo electrónico",
                required: false,
                autofocus: true,
                input_html: { autocomplete: "email" } %>
    <%= f.input :password,
                label: "Contraseña",
                required: false,
                input_html: { autocomplete: "current-password" } %>
    <%= f.input :remember_me, label: "Recordarme", as: :boolean if devise_mapping.rememberable? %>
  </div>

  <div class="form-actions">
    <%= f.button :submit, "Iniciar sesión" %>
  </div>
<% end %>

<%= render "devise/shared/links" %>
```

- [x] **Step 4: Quitar el registro y traducir el partial de enlaces**

Reemplazar TODO el contenido de `app/views/devise/shared/_links.html.erb` por (se elimina por completo el bloque `if devise_mapping.registerable?`, de modo que no aparece "Crear cuenta" en ninguna vista de Devise):

```erb
<%- if controller_name != 'sessions' %>
  <p><%= link_to "Iniciar sesión", new_session_path(resource_name) %></p>
<% end %>

<%# Registro deshabilitado en la cara pública: no se muestra enlace de "Crear cuenta". %>

<%- if devise_mapping.recoverable? && controller_name != 'passwords' && controller_name != 'registrations' %>
  <p><%= link_to "¿Olvidaste tu contraseña?", new_password_path(resource_name) %></p>
<% end %>

<%- if devise_mapping.confirmable? && controller_name != 'confirmations' %>
  <p><%= link_to "¿No recibiste instrucciones de confirmación?", new_confirmation_path(resource_name) %></p>
<% end %>

<%- if devise_mapping.lockable? && resource_class.unlock_strategy_enabled?(:email) && controller_name != 'unlocks' %>
  <p><%= link_to "¿No recibiste instrucciones de desbloqueo?", new_unlock_path(resource_name) %></p>
<% end %>

<%- if devise_mapping.omniauthable? %>
  <%- resource_class.omniauth_providers.each do |provider| %>
    <p><%= button_to "Iniciar sesión con #{OmniAuth::Utils.camelize(provider)}", omniauth_authorize_path(resource_name, provider), data: { turbo: false } %></p>
  <% end %>
<% end %>
```

- [x] **Step 5: Ejecutar el test y verificar que pasa**

Run: `bin/rails test test/integration/login_page_test.rb`
Expected: PASS (2 runs, 0 failures).

- [x] **Step 6: Commit**

```bash
git add test/integration/login_page_test.rb app/views/devise/sessions/new.html.erb app/views/devise/shared/_links.html.erb
git commit -m "feat: Spanish login page without registration link

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Verificación final

**Files:** ninguno (solo verificación)

- [x] **Step 1: Ejecutar toda la suite de tests**

Run: `bin/rails test`
Expected: PASS — incluyendo `home_landing_test`, `login_page_test` y los `role_routing_test` existentes, todos verdes.

- [x] **Step 2: Ejecutar el pipeline de CI completo**

Run: `bin/ci`
Expected: todos los pasos en verde (Setup, RuboCop, los tres scanners de seguridad, Tests: Rails, Tests: Seeds).

- [x] **Step 3: Recorrido manual del flujo completo**

Run: `bin/dev`. Con las cuentas del seed (ver credenciales en `db/seeds.rb`):
1. Abrir `http://localhost:3000/` sin sesión → se ve la landing.
2. Clic en "Iniciar sesión" → página de login en español, sin enlace "Crear cuenta".
3. Iniciar sesión como **manager** → redirige al tablero (`/manager/orders`).
4. Cerrar sesión, iniciar como **repartidor** → redirige a "Mis entregas" (`/rider/orders`).

Detener con Ctrl-C.

- [x] **Step 4: Verificación de redirección de usuarios autenticados (ya cubierta)**

`role_routing_test.rb` ya garantiza que un usuario autenticado que visita `/` es redirigido a su dashboard. Confirmar que esos 4 tests siguen verdes en el output del Step 1. No requiere cambios.
