# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

A food-delivery app in the style of Uber Eats — customers browse restaurants/menus, place orders, and track them; the domain centers on restaurants, menu items, orders, and deliveries. Live order/delivery tracking is delivered over **Turbo Streams + Action Cable**, backed by **Solid Cable** (the Solid trifecta's DB-backed cable adapter — no Redis). Broadcast model changes with `broadcast_*_to` / `turbo_stream_from` rather than polling.

## Stack

Rails 8.1 app (Ruby 3.3.5) on PostgreSQL, generated from the [Le Wagon rails-templates](https://github.com/lewagon/rails-templates). Hotwire (Turbo + Stimulus) via **importmap** (no Node/bundler — there is no `package.json`), Bootstrap 5.3 + `simple_form` for views, and the Rails 8 "Solid" trifecta (`solid_queue`, `solid_cache`, `solid_cable`) so jobs/cache/cable are DB-backed (no Redis). Deploy is Kamal + Docker.

## Commands

```bash
bin/setup            # install gems, prepare DB, start server (use --skip-server to stop before booting)
bin/dev              # run the app (alias for bin/rails server)
bin/rails db:migrate # after adding a migration; bin/rails db:create first on a fresh machine

bin/rails test                              # full test suite (Minitest)
bin/rails test test/models/user_test.rb     # single file
bin/rails test test/models/user_test.rb:7   # single test by line number
bin/rails test:system                       # Capybara/Selenium system tests (not run in CI by default)

bin/rubocop          # lint (rubocop-rails-omakase, tuned in .rubocop.yml)
bin/ci               # full CI pipeline locally — see config/ci.rb
```

`bin/ci` is the source of truth for "is this mergeable": it runs setup, RuboCop, three security scanners (`bin/bundler-audit`, `bin/importmap audit`, `bin/brakeman`), the test suite, and `db:seed:replant`. Run it before considering work done.

## Architecture notes

- **Authentication is global and opt-out.** `ApplicationController` declares `before_action :authenticate_user!` (Devise), so *every* controller action requires a logged-in user by default. Public actions must explicitly opt out, e.g. `PagesController` uses `skip_before_action :authenticate_user!, only: [:home]`. Remember this when adding any publicly reachable endpoint.

- **Devise `User`** uses `database_authenticatable`, `registerable`, `recoverable`, `rememberable`, `validatable`. Devise views are already generated under `app/views/devise/` and styled with simple_form/Bootstrap — edit them in place rather than regenerating.

- **JavaScript is importmap-pinned.** Add libraries with `bin/importmap pin <pkg>` (writes to `config/importmap.rb`); there is no transpile/build step. Stimulus controllers in `app/javascript/controllers/` are auto-registered.

- **Styles** live in `app/assets/stylesheets/` split into `config/` (colors, fonts, Bootstrap variable overrides), `components/`, and `pages/`, each with an `_index.scss` imported by `application.scss`. Bootstrap variables must be overridden in `config/_bootstrap_variables.scss` *before* Bootstrap is imported.

- **Scaffolds use simple_form.** `lib/templates/erb/scaffold/_form.html.erb` overrides the default generator so `rails g scaffold` produces simple_form markup.

- **Generators** are configured in `config/application.rb` to skip assets and helpers and to use `test_unit` without fixtures.

- **Production uses four separate PostgreSQL databases** (primary, cache, queue, cable — see `config/database.yml`), each with its own `migrations_paths`. Development/test use a single DB.

## Environment

`.env` (via `dotenv-rails`, dev/test only) holds local env vars. Secrets are managed through Rails encrypted credentials (`config/credentials.yml.enc` + `config/master.key`) and, for deploys, `.kamal/secrets`.
