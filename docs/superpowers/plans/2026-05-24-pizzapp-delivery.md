# PizzApp Delivery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a single-restaurant delivery app where a manager registers/assigns orders and riders advance them through a delivery lifecycle, shown on a kanban board.

**Architecture:** Rails 8.1 + Hotwire (importmap, no build step). One `User` model with a `role` enum (manager/rider). `Order has_many :order_items`, each `OrderItem belongs_to :product` with a snapshotted `unit_price`. Role-namespaced controllers (`Manager::`, `Rider::`) enforce authorization via a per-namespace base controller plus query scoping. Addresses are geocoded with the `geocoder` gem and shown on a Mapbox map via a Stimulus controller. No real-time/Turbo Streams in this MVP — plain page reloads.

**Tech Stack:** Ruby 3.3.5, Rails 8.1, PostgreSQL, Devise, simple_form + Bootstrap 5.3, importmap + Stimulus, geocoder, Mapbox GL JS, Minitest.

**Spec:** `docs/superpowers/specs/2026-05-24-pizzapp-delivery-design.md`
**Visual reference (approved mockup):** `.superpowers/brainstorm/9705-1779610060/content/kanban-final.html`

**Conventions discovered in this repo (follow them):**
- `ApplicationController` already has `before_action :authenticate_user!` globally; public actions opt out with `skip_before_action`.
- Generators are configured (`config/application.rb`) to skip assets/helpers and use `test_unit` **without fixtures** — tests create records inline.
- Stylesheets: `app/assets/stylesheets/application.scss` imports `config/fonts`, `config/colors`, `config/bootstrap_variables` (in that order, before Bootstrap), then `components/index` and `pages/index`. There is **no** `config/_index.scss`.
- simple_form + Bootstrap are installed and initialized.
- RuboCop is `rubocop-rails-omakase` (double-quoted strings, 2-space indent). Run `bin/rubocop -a` before each commit.
- `bin/ci` is the merge gate (RuboCop, bundler-audit, importmap audit, brakeman, tests, `db:seed:replant`).

---

## Task 1: Add the `geocoder` gem and configure it (incl. test stub)

**Files:**
- Modify: `Gemfile`
- Create: `config/initializers/geocoder.rb`
- Modify: `test/test_helper.rb`

- [x] **Step 1: Add the gem**

In `Gemfile`, add after the `gem "devise"` line:

```ruby
gem "geocoder"
```

- [x] **Step 2: Install**

Run: `bundle install`
Expected: bundle completes, `geocoder` resolved.

- [x] **Step 3: Configure geocoder (Mapbox provider)**

Create `config/initializers/geocoder.rb`:

```ruby
Geocoder.configure(
  lookup: :mapbox,
  api_key: ENV["MAPBOX_API_KEY"],
  units: :km,
  timeout: 5
)
```

- [x] **Step 4: Stub geocoding in tests so the suite never hits the network**

In `test/test_helper.rb`, add after `require "rails/test_help"`:

```ruby
# Geocoding: never hit the network in tests — return fixed coordinates.
Geocoder.configure(lookup: :test, ip_lookup: :test)
Geocoder::Lookup::Test.set_default_stub(
  [{ "coordinates" => [19.4326, -99.1332], "address" => "Ciudad de México, CDMX, México" }]
)
```

- [x] **Step 5: Verify the app still boots**

Run: `bin/rails runner "puts Geocoder.config.lookup"`
Expected: prints `mapbox` (or `test` under RAILS_ENV=test).

- [x] **Step 6: Commit**

```bash
bin/rubocop -a
git add Gemfile Gemfile.lock config/initializers/geocoder.rb test/test_helper.rb
git commit -m "chore: add and configure geocoder with test stub"
```

---

## Task 2: Add `role` to `User`

**Files:**
- Create: `db/migrate/*_add_role_to_users.rb` (via generator)
- Modify: `app/models/user.rb`
- Modify: `test/models/user_test.rb`

- [x] **Step 1: Generate the migration**

Run: `bin/rails g migration AddRoleToUsers role:integer`

- [x] **Step 2: Edit the migration to add default + null:false + index**

Replace the generated `db/migrate/*_add_role_to_users.rb` body with:

```ruby
class AddRoleToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :role, :integer, default: 1, null: false
    add_index :users, :role
  end
end
```

(`1` = `rider`, the default for new sign-ups.)

- [x] **Step 3: Migrate**

Run: `bin/rails db:migrate`
Expected: `users` gains a `role` column.

- [x] **Step 4: Write the failing test**

Replace `test/models/user_test.rb` with:

```ruby
require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "defaults to rider" do
    user = User.new(email: "new@example.com", password: "password123")
    assert user.rider?
    assert_not user.manager?
  end

  test "can be a manager" do
    user = User.create!(email: "boss@example.com", password: "password123", role: :manager)
    assert user.manager?
    assert_includes User.manager, user
  end

  test "assigned_orders association exists" do
    user = User.new(role: :rider)
    assert_respond_to user, :assigned_orders
  end
end
```

- [x] **Step 5: Run it — expect failure**

Run: `bin/rails test test/models/user_test.rb`
Expected: FAIL (`NoMethodError: undefined method 'rider?'`).

- [x] **Step 6: Implement the model changes**

Replace `app/models/user.rb` with:

```ruby
class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  enum :role, { manager: 0, rider: 1 }, default: :rider

  has_many :assigned_orders, class_name: "Order", foreign_key: :rider_id, dependent: :nullify
end
```

- [x] **Step 7: Run it — expect pass**

Run: `bin/rails test test/models/user_test.rb`
Expected: PASS (3 runs, 0 failures). The `assigned_orders` test passes even though `Order` doesn't exist yet because the association is lazy.

- [x] **Step 8: Commit**

```bash
bin/rubocop -a
git add db/migrate app/models/user.rb test/models/user_test.rb db/schema.rb
git commit -m "feat: add role enum and assigned_orders to User"
```

---

## Task 3: `Product` model

**Files:**
- Create: `db/migrate/*_create_products.rb`, `app/models/product.rb` (via generator)
- Modify: the generated `test/models/product_test.rb`

- [x] **Step 1: Generate the model**

Run: `bin/rails g model Product name:string price:decimal`

- [x] **Step 2: Edit the migration for precision + null:false**

Replace the generated `db/migrate/*_create_products.rb` body with:

```ruby
class CreateProducts < ActiveRecord::Migration[8.1]
  def change
    create_table :products do |t|
      t.string :name, null: false
      t.decimal :price, precision: 8, scale: 2, null: false

      t.timestamps
    end
  end
end
```

- [x] **Step 3: Migrate**

Run: `bin/rails db:migrate`

- [x] **Step 4: Write the failing test**

Replace `test/models/product_test.rb` with:

```ruby
require "test_helper"

class ProductTest < ActiveSupport::TestCase
  test "valid with name and price" do
    assert Product.new(name: "Margarita", price: 150).valid?
  end

  test "requires a name" do
    product = Product.new(price: 150)
    assert_not product.valid?
    assert_includes product.errors[:name], "can't be blank"
  end

  test "requires a non-negative price" do
    assert_not Product.new(name: "Margarita", price: nil).valid?
    assert_not Product.new(name: "Margarita", price: -1).valid?
  end
end
```

- [x] **Step 5: Run it — expect failure**

Run: `bin/rails test test/models/product_test.rb`
Expected: FAIL (no validations yet — invalid records are reported valid).

- [x] **Step 6: Implement the model**

Replace `app/models/product.rb` with:

```ruby
class Product < ApplicationRecord
  has_many :order_items, dependent: :restrict_with_error

  validates :name, presence: true
  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }
end
```

- [x] **Step 7: Run it — expect pass**

Run: `bin/rails test test/models/product_test.rb`
Expected: PASS (3 runs, 0 failures).

- [x] **Step 8: Commit**

```bash
bin/rubocop -a
git add db/migrate app/models/product.rb test/models/product_test.rb db/schema.rb
git commit -m "feat: add Product model"
```

---

## Task 4: `Order` model — schema, status enum, presence validations

**Files:**
- Create: `db/migrate/*_create_orders.rb`, `app/models/order.rb` (via generator)
- Modify: the generated `test/models/order_test.rb`

- [x] **Step 1: Generate the model**

Run: `bin/rails g model Order recipient_name:string recipient_phone:string address:string latitude:float longitude:float status:integer rider:references`

- [x] **Step 2: Edit the migration (null/defaults; rider FK → users; nullable rider)**

Replace the generated `db/migrate/*_create_orders.rb` body with:

```ruby
class CreateOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :orders do |t|
      t.string :recipient_name, null: false
      t.string :recipient_phone, null: false
      t.string :address, null: false
      t.float :latitude
      t.float :longitude
      t.integer :status, null: false, default: 0
      t.references :rider, foreign_key: { to_table: :users }

      t.timestamps
    end
  end
end
```

(`status` default `0` = `pending`. `rider` is nullable — no `null: false` — so a pending order has no rider.)

- [x] **Step 3: Migrate**

Run: `bin/rails db:migrate`

- [x] **Step 4: Write the failing test**

Replace `test/models/order_test.rb` with:

```ruby
require "test_helper"

class OrderTest < ActiveSupport::TestCase
  def valid_attrs
    { recipient_name: "Ana Gómez", recipient_phone: "5512345678", address: "Colima 143, CDMX" }
  end

  test "defaults to pending with no rider" do
    order = Order.new(valid_attrs)
    assert order.pending?
    assert_nil order.rider
  end

  test "requires recipient_name, recipient_phone, address" do
    order = Order.new
    assert_not order.valid?
    assert_includes order.errors[:recipient_name], "can't be blank"
    assert_includes order.errors[:recipient_phone], "can't be blank"
    assert_includes order.errors[:address], "can't be blank"
  end

  test "rider is optional" do
    order = Order.new(valid_attrs)
    order.valid?
    assert_empty order.errors[:rider]
  end
end
```

- [x] **Step 5: Run it — expect failure**

Run: `bin/rails test test/models/order_test.rb`
Expected: FAIL (`belongs_to :rider` is required by default, so "rider is optional" fails; no presence validations yet).

- [x] **Step 6: Implement the model**

Replace `app/models/order.rb` with:

```ruby
class Order < ApplicationRecord
  enum :status, { pending: 0, assigned: 1, en_route: 2, delivered: 3 }, default: :pending

  belongs_to :rider, class_name: "User", optional: true

  validates :recipient_name, :recipient_phone, :address, presence: true
end
```

- [x] **Step 7: Run it — expect pass**

Run: `bin/rails test test/models/order_test.rb`
Expected: PASS (3 runs, 0 failures).

- [x] **Step 8: Commit**

```bash
bin/rubocop -a
git add db/migrate app/models/order.rb test/models/order_test.rb db/schema.rb
git commit -m "feat: add Order model with status enum and validations"
```

---

## Task 5: `OrderItem` model — unit_price snapshot, quantity, subtotal

**Files:**
- Create: `db/migrate/*_create_order_items.rb`, `app/models/order_item.rb` (via generator)
- Modify: the generated `test/models/order_item_test.rb`

- [x] **Step 1: Generate the model**

Run: `bin/rails g model OrderItem order:references product:references unit_price:decimal quantity:integer`

- [x] **Step 2: Edit the migration (precision, null:false, quantity default)**

Replace the generated `db/migrate/*_create_order_items.rb` body with:

```ruby
class CreateOrderItems < ActiveRecord::Migration[8.1]
  def change
    create_table :order_items do |t|
      t.references :order, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.decimal :unit_price, precision: 8, scale: 2, null: false
      t.integer :quantity, null: false, default: 1

      t.timestamps
    end
  end
end
```

- [x] **Step 3: Migrate**

Run: `bin/rails db:migrate`

- [x] **Step 4: Write the failing test**

Replace `test/models/order_item_test.rb` with:

```ruby
require "test_helper"

class OrderItemTest < ActiveSupport::TestCase
  setup do
    @order = Order.new(recipient_name: "Ana", recipient_phone: "55", address: "CDMX")
    @product = Product.create!(name: "Margarita", price: 150)
  end

  test "copies unit_price from product on create when blank" do
    item = OrderItem.new(order: @order, product: @product, quantity: 2)
    item.valid?
    assert_equal 150, item.unit_price
  end

  test "keeps an explicitly set unit_price (snapshot)" do
    item = OrderItem.new(order: @order, product: @product, quantity: 1, unit_price: 99)
    item.valid?
    assert_equal 99, item.unit_price
  end

  test "subtotal is unit_price times quantity" do
    item = OrderItem.new(order: @order, product: @product, quantity: 3, unit_price: 150)
    assert_equal 450, item.subtotal
  end

  test "quantity must be a positive integer" do
    item = OrderItem.new(order: @order, product: @product, quantity: 0)
    assert_not item.valid?
    assert_includes item.errors[:quantity], "must be greater than 0"
  end
end
```

- [x] **Step 5: Run it — expect failure**

Run: `bin/rails test test/models/order_item_test.rb`
Expected: FAIL (`undefined method 'subtotal'`; no unit_price copy/validation yet).

- [x] **Step 6: Implement the model**

Replace `app/models/order_item.rb` with:

```ruby
class OrderItem < ApplicationRecord
  belongs_to :order
  belongs_to :product

  before_validation :copy_unit_price_from_product, on: :create

  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :unit_price, presence: true, numericality: { greater_than_or_equal_to: 0 }

  def subtotal
    (unit_price || 0) * (quantity || 0)
  end

  private

  def copy_unit_price_from_product
    self.unit_price ||= product&.price
  end
end
```

- [x] **Step 7: Run it — expect pass**

Run: `bin/rails test test/models/order_item_test.rb`
Expected: PASS (4 runs, 0 failures).

- [x] **Step 8: Commit**

```bash
bin/rubocop -a
git add db/migrate app/models/order_item.rb test/models/order_item_test.rb db/schema.rb
git commit -m "feat: add OrderItem model with unit_price snapshot and subtotal"
```

---

## Task 6: Wire `Order` ↔ `OrderItem` — nested attributes, total, at-least-one-item, transitions

**Files:**
- Modify: `app/models/order.rb`
- Modify: `test/models/order_test.rb`

- [x] **Step 1: Add the failing tests**

Append these tests inside `test/models/order_test.rb` (before the final `end`):

```ruby
  test "total sums the subtotals of its items" do
    margarita = Product.create!(name: "Margarita", price: 150)
    soda = Product.create!(name: "Coca-Cola", price: 30)
    order = Order.new(valid_attrs)
    order.order_items.build(product: margarita, quantity: 2) # 300
    order.order_items.build(product: soda, quantity: 1)      # 30
    assert_equal 330, order.total
  end

  test "is invalid without at least one item" do
    order = Order.new(valid_attrs)
    assert_not order.valid?
    assert_includes order.errors[:base], "must have at least one item"
  end

  test "is valid with one item" do
    product = Product.create!(name: "Margarita", price: 150)
    order = Order.new(valid_attrs)
    order.order_items.build(product: product, quantity: 1)
    assert order.valid?
  end

  test "assign_to! moves pending -> assigned and sets the rider" do
    rider = User.create!(email: "r@example.com", password: "password123", role: :rider)
    order = create_order
    assert order.assign_to!(rider)
    assert order.reload.assigned?
    assert_equal rider, order.rider
  end

  test "assign_to! is rejected when not pending" do
    rider = User.create!(email: "r2@example.com", password: "password123", role: :rider)
    order = create_order
    order.assign_to!(rider)
    assert_not order.assign_to!(rider) # already assigned
  end

  test "mark_en_route! requires assigned, mark_delivered! requires en_route" do
    rider = User.create!(email: "r3@example.com", password: "password123", role: :rider)
    order = create_order
    assert_not order.mark_en_route!          # still pending
    order.assign_to!(rider)
    assert order.mark_en_route!
    assert order.reload.en_route?
    assert order.mark_delivered!
    assert order.reload.delivered?
  end

  private

  def create_order
    product = Product.create!(name: "Margarita", price: 150)
    order = Order.new(valid_attrs)
    order.order_items.build(product: product, quantity: 1)
    order.save!
    order
  end
```

- [x] **Step 2: Run it — expect failure**

Run: `bin/rails test test/models/order_test.rb`
Expected: FAIL (`undefined method 'order_items'` / `total` / `assign_to!`).

- [x] **Step 3: Implement the wiring**

Replace `app/models/order.rb` with:

```ruby
class Order < ApplicationRecord
  enum :status, { pending: 0, assigned: 1, en_route: 2, delivered: 3 }, default: :pending

  belongs_to :rider, class_name: "User", optional: true
  has_many :order_items, dependent: :destroy
  accepts_nested_attributes_for :order_items, allow_destroy: true, reject_if: :all_blank

  validates :recipient_name, :recipient_phone, :address, presence: true
  validate :must_have_at_least_one_item

  def total
    order_items.reject(&:marked_for_destruction?).sum(&:subtotal)
  end

  def assign_to!(rider)
    return false unless pending?

    update(rider: rider, status: :assigned)
  end

  def mark_en_route!
    return false unless assigned?

    update(status: :en_route)
  end

  def mark_delivered!
    return false unless en_route?

    update(status: :delivered)
  end

  private

  def must_have_at_least_one_item
    return if order_items.reject(&:marked_for_destruction?).any?

    errors.add(:base, "must have at least one item")
  end
end
```

- [x] **Step 4: Run it — expect pass**

Run: `bin/rails test test/models/order_test.rb`
Expected: PASS (all order tests green).

- [x] **Step 5: Run the full model suite**

Run: `bin/rails test test/models`
Expected: PASS (User, Product, Order, OrderItem).

- [x] **Step 6: Commit**

```bash
bin/rubocop -a
git add app/models/order.rb test/models/order_test.rb
git commit -m "feat: wire Order items, total and status transitions"
```

---

## Task 7: Geocode `Order` addresses

**Files:**
- Modify: `app/models/order.rb`
- Modify: `test/models/order_test.rb`

- [x] **Step 1: Add the failing test**

Add inside `test/models/order_test.rb` (after the "is valid with one item" test, before `private`):

```ruby
  test "geocodes the address on save" do
    order = create_order
    assert_equal 19.4326, order.latitude
    assert_equal(-99.1332, order.longitude)
  end

  test "does not re-geocode when address is unchanged" do
    order = create_order
    order.latitude = 0.0
    order.longitude = 0.0
    order.update!(recipient_name: "Otra persona") # address unchanged
    assert_equal 0.0, order.latitude # geocode callback did not overwrite
  end
```

(The fixed coordinates come from the test stub in `test/test_helper.rb`.)

- [x] **Step 2: Run it — expect failure**

Run: `bin/rails test test/models/order_test.rb`
Expected: FAIL (`latitude` is nil — no geocoding yet).

- [x] **Step 3: Add geocoding to the model**

In `app/models/order.rb`, add the geocoder lines directly under the `validate :must_have_at_least_one_item` line:

```ruby
  geocoded_by :address
  after_validation :geocode, if: -> { address.present? && address_changed? }
```

- [x] **Step 4: Run it — expect pass**

Run: `bin/rails test test/models/order_test.rb`
Expected: PASS.

- [x] **Step 5: Commit**

```bash
bin/rubocop -a
git add app/models/order.rb test/models/order_test.rb
git commit -m "feat: geocode Order addresses with geocoder"
```

---

## Task 8: Routing, role-based redirects, and namespace base controllers

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/controllers/application_controller.rb`
- Modify: `app/controllers/pages_controller.rb`
- Create: `app/controllers/manager/base_controller.rb`
- Create: `app/controllers/rider/base_controller.rb`
- Modify: `test/test_helper.rb` (Devise integration sign-in helper)
- Create: `test/integration/role_routing_test.rb`

- [x] **Step 1: Add the routes**

Replace the body of `config/routes.rb`'s `draw` block (keep the health-check and PWA comments) so it reads:

```ruby
Rails.application.routes.draw do
  devise_for :users
  root to: "pages#home"

  namespace :manager do
    resources :orders, only: [ :index, :new, :create, :show, :update ]
  end

  namespace :rider do
    resources :orders, only: [ :index, :show, :update ]
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check
end
```

- [x] **Step 2: Enable Devise sign-in in integration tests**

In `test/test_helper.rb`, add a new block after the `ActiveSupport::TestCase` class:

```ruby
class ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
end
```

- [x] **Step 3: Write the failing test**

Create `test/integration/role_routing_test.rb`:

```ruby
require "test_helper"

class RoleRoutingTest < ActionDispatch::IntegrationTest
  setup do
    @manager = User.create!(email: "boss@example.com", password: "password123", role: :manager)
    @rider = User.create!(email: "rider@example.com", password: "password123", role: :rider)
  end

  test "manager signing in lands on the manager board" do
    sign_in @manager
    get root_path
    assert_redirected_to manager_orders_path
  end

  test "rider signing in lands on rider deliveries" do
    sign_in @rider
    get root_path
    assert_redirected_to rider_orders_path
  end

  test "rider cannot access the manager namespace" do
    sign_in @rider
    get manager_orders_path
    assert_redirected_to root_path
  end

  test "manager cannot access the rider namespace" do
    sign_in @manager
    get rider_orders_path
    assert_redirected_to root_path
  end
end
```

- [x] **Step 4: Run it — expect failure**

Run: `bin/rails test test/integration/role_routing_test.rb`
Expected: FAIL (no namespace controllers; no redirect logic).

- [x] **Step 5: Add role redirect to ApplicationController**

Replace `app/controllers/application_controller.rb` with:

```ruby
class ApplicationController < ActionController::Base
  before_action :authenticate_user!

  def after_sign_in_path_for(resource)
    dashboard_path_for(resource)
  end

  private

  def dashboard_path_for(user)
    user.manager? ? manager_orders_path : rider_orders_path
  end
end
```

- [x] **Step 6: Redirect signed-in users from home to their dashboard**

Replace `app/controllers/pages_controller.rb` with:

```ruby
class PagesController < ApplicationController
  skip_before_action :authenticate_user!, only: [ :home ]

  def home
    redirect_to dashboard_path_for(current_user) if user_signed_in?
  end
end
```

- [x] **Step 7: Create the manager base controller**

Create `app/controllers/manager/base_controller.rb`:

```ruby
class Manager::BaseController < ApplicationController
  before_action :require_manager

  private

  def require_manager
    redirect_to root_path, alert: "No tienes acceso a esa sección." unless current_user.manager?
  end
end
```

- [x] **Step 8: Create the rider base controller**

Create `app/controllers/rider/base_controller.rb`:

```ruby
class Rider::BaseController < ApplicationController
  before_action :require_rider

  private

  def require_rider
    redirect_to root_path, alert: "No tienes acceso a esa sección." unless current_user.rider?
  end
end
```

- [x] **Step 9: Create placeholder namespace controllers so routes resolve**

Create `app/controllers/manager/orders_controller.rb`:

```ruby
class Manager::OrdersController < Manager::BaseController
  def index
    @orders = []
  end
end
```

Create `app/controllers/rider/orders_controller.rb`:

```ruby
class Rider::OrdersController < Rider::BaseController
  def index
    @orders = []
  end
end
```

(These are fleshed out in later tasks; for now they only need to exist so the authorization redirects are exercised. The index views are added in Tasks 9 and 12 — until then these tasks' own tests target redirects, which happen in the `before_action` before any view renders.)

- [x] **Step 10: Run it — expect pass**

Run: `bin/rails test test/integration/role_routing_test.rb`
Expected: PASS (4 runs, 0 failures).

- [x] **Step 11: Commit**

```bash
bin/rubocop -a
git add config/routes.rb app/controllers test/test_helper.rb test/integration/role_routing_test.rb
git commit -m "feat: role-namespaced routing with authorization redirects"
```

---

## Task 9: Manager kanban board (`index`)

**Files:**
- Modify: `app/controllers/manager/orders_controller.rb`
- Create: `app/views/manager/orders/index.html.erb`
- Create: `app/views/manager/orders/_card.html.erb`
- Create: `test/integration/manager_orders_test.rb`

- [x] **Step 1: Write the failing test**

Create `test/integration/manager_orders_test.rb`:

```ruby
require "test_helper"

class ManagerOrdersTest < ActionDispatch::IntegrationTest
  setup do
    @manager = User.create!(email: "boss@example.com", password: "password123", role: :manager)
    @rider = User.create!(email: "rider@example.com", password: "password123", role: :rider)
    @product = Product.create!(name: "Margarita", price: 150)
    sign_in @manager
  end

  def create_order(status: :pending, rider: nil)
    order = Order.new(recipient_name: "Ana", recipient_phone: "55", address: "CDMX", status: status, rider: rider)
    order.order_items.build(product: @product, quantity: 2)
    order.save!
    order
  end

  test "index shows every order grouped by status" do
    create_order(status: :pending)
    create_order(status: :delivered, rider: @rider)
    get manager_orders_path
    assert_response :success
    assert_select ".kanban-column", 4
    assert_select ".order-card", 2
  end
end
```

- [x] **Step 2: Run it — expect failure**

Run: `bin/rails test test/integration/manager_orders_test.rb`
Expected: FAIL (missing template / `kanban-column` not found).

- [x] **Step 3: Implement the index action**

Replace `app/controllers/manager/orders_controller.rb` with:

```ruby
class Manager::OrdersController < Manager::BaseController
  STATUS_LABELS = {
    "pending" => "Pendiente",
    "assigned" => "Asignada",
    "en_route" => "En camino",
    "delivered" => "Entregada"
  }.freeze

  def index
    orders = Order.includes(:rider, order_items: :product).order(created_at: :desc)
    @orders_by_status = orders.group_by(&:status)
  end
end
```

- [x] **Step 4: Create the order card partial**

Create `app/views/manager/orders/_card.html.erb`:

```erb
<%= link_to manager_order_path(order), class: "order-card order-card--#{order.status}" do %>
  <div class="order-card__top">
    <span class="status-pill status-pill--<%= order.status %>">
      <span class="status-pill__dot"></span>
      <%= Manager::OrdersController::STATUS_LABELS[order.status] %>
    </span>
    <span class="order-card__time"><%= time_ago_in_words(order.created_at) %></span>
  </div>

  <div class="order-card__name"><%= order.recipient_name %></div>

  <div class="order-card__addr">
    <i class="fa-solid fa-location-dot"></i>
    <%= order.address %>
  </div>

  <div class="order-card__items">
    <%= order.order_items.map { |i| "#{i.quantity}× #{i.product.name}" }.join(" · ") %>
  </div>

  <hr class="order-card__sep">

  <div class="order-card__bottom">
    <% if order.rider %>
      <span class="order-card__rider"><%= order.rider.email.split("@").first %></span>
    <% else %>
      <span class="order-card__unassigned">Sin asignar</span>
    <% end %>
    <span class="order-card__total">$<%= number_with_delimiter(order.total) %></span>
  </div>
<% end %>
```

- [x] **Step 5: Create the kanban index view**

Create `app/views/manager/orders/index.html.erb`:

```erb
<% content_for :title, "Tablero de órdenes" %>

<div class="board">
  <header class="board__top">
    <div>
      <h1 class="board__title">Tablero de órdenes</h1>
      <p class="board__sub"><%= Order.where.not(status: :delivered).count %> órdenes activas</p>
    </div>
    <%= link_to new_manager_order_path, class: "btn btn-brand" do %>
      <i class="fa-solid fa-plus"></i> Nueva orden
    <% end %>
  </header>

  <div class="kanban">
    <% Order.statuses.each_key do |status| %>
      <% orders = @orders_by_status[status] || [] %>
      <section class="kanban-column kanban-column--<%= status %>">
        <div class="kanban-column__head">
          <span class="kanban-column__dot"></span>
          <span class="kanban-column__title"><%= Manager::OrdersController::STATUS_LABELS[status] %></span>
          <span class="kanban-column__count"><%= orders.size %></span>
        </div>
        <%= render partial: "card", collection: orders, as: :order %>
      </section>
    <% end %>
  </div>
</div>
```

- [x] **Step 6: Run it — expect pass**

Run: `bin/rails test test/integration/manager_orders_test.rb`
Expected: PASS.

- [x] **Step 7: Commit**

```bash
bin/rubocop -a
git add app/controllers/manager/orders_controller.rb app/views/manager/orders test/integration/manager_orders_test.rb
git commit -m "feat: manager kanban board index"
```

---

## Task 10: Manager — new/create order with dynamic line items

**Files:**
- Modify: `app/controllers/manager/orders_controller.rb`
- Create: `app/views/manager/orders/new.html.erb`
- Create: `app/views/manager/orders/_form.html.erb`
- Create: `app/views/manager/orders/_order_item_fields.html.erb`
- Create: `app/javascript/controllers/order_form_controller.js`
- Modify: `test/integration/manager_orders_test.rb`

- [x] **Step 1: Write the failing test**

Add inside `test/integration/manager_orders_test.rb` (before the final `end`):

```ruby
  test "new renders the order form" do
    get new_manager_order_path
    assert_response :success
    assert_select "form"
    assert_select "input[name='order[recipient_name]']"
  end

  test "create persists an order with items and redirects to it" do
    assert_difference [ "Order.count", "OrderItem.count" ], 1 do
      post manager_orders_path, params: {
        order: {
          recipient_name: "Ana", recipient_phone: "55", address: "Colima 143, CDMX",
          order_items_attributes: { "0" => { product_id: @product.id, quantity: "2" } }
        }
      }
    end
    order = Order.last
    assert_redirected_to manager_order_path(order)
    assert_equal 300, order.total            # 150 * 2 snapshot
    assert_equal 150, order.order_items.first.unit_price
  end

  test "create re-renders with errors when invalid" do
    assert_no_difference "Order.count" do
      post manager_orders_path, params: {
        order: { recipient_name: "", recipient_phone: "", address: "" }
      }
    end
    assert_response :unprocessable_entity
  end
```

- [x] **Step 2: Run it — expect failure**

Run: `bin/rails test test/integration/manager_orders_test.rb`
Expected: FAIL (no `new`/`create` actions or templates).

- [x] **Step 3: Add new/create to the controller**

In `app/controllers/manager/orders_controller.rb`, add these actions after `index`:

```ruby
  def new
    @order = Order.new
    @order.order_items.build
    @products = Product.order(:name)
  end

  def create
    @order = Order.new(order_params)
    if @order.save
      redirect_to manager_order_path(@order), notice: "Orden creada."
    else
      @products = Product.order(:name)
      render :new, status: :unprocessable_entity
    end
  end
```

And add the strong-params method in the `private` section (add a `private` keyword at the end of the class if not present):

```ruby
  private

  def order_params
    params.require(:order).permit(
      :recipient_name, :recipient_phone, :address,
      order_items_attributes: [ :id, :product_id, :quantity, :_destroy ]
    )
  end
```

- [x] **Step 4: Create the line-item fields partial**

Create `app/views/manager/orders/_order_item_fields.html.erb`:

```erb
<div class="order-line" data-order-form-target="line">
  <%= f.association :product,
        collection: products,
        label_method: :name,
        value_method: :id,
        include_blank: "Elegí un producto",
        label: false,
        wrapper: false %>
  <%= f.input :quantity,
        label: false,
        input_html: { value: f.object.quantity || 1, min: 1, class: "order-line__qty" },
        wrapper: false %>
  <%= f.input :_destroy, as: :hidden %>
  <button type="button" class="order-line__remove" data-action="order-form#remove" aria-label="Quitar">
    <i class="fa-solid fa-xmark"></i>
  </button>
</div>
```

- [x] **Step 5: Create the form partial (with a `<template>` for new rows)**

Create `app/views/manager/orders/_form.html.erb`:

```erb
<%= simple_form_for [ :manager, @order ], html: { data: { controller: "order-form" }, class: "order-form" } do |f| %>
  <%= f.error_notification %>
  <%= f.error_notification message: f.object.errors[:base].to_sentence if f.object.errors[:base].present? %>

  <%= f.input :recipient_name, label: "Nombre del destinatario" %>
  <%= f.input :recipient_phone, label: "Teléfono" %>
  <%= f.input :address, label: "Dirección de entrega" %>

  <fieldset class="order-form__items">
    <legend>Productos</legend>

    <div data-order-form-target="lines">
      <%= f.simple_fields_for :order_items do |item| %>
        <%= render "order_item_fields", f: item, products: @products %>
      <% end %>
    </div>

    <template data-order-form-target="template">
      <%= f.simple_fields_for :order_items, OrderItem.new, child_index: "NEW_RECORD" do |item| %>
        <%= render "order_item_fields", f: item, products: @products %>
      <% end %>
    </template>

    <button type="button" class="btn btn-outline-brand" data-action="order-form#add">
      <i class="fa-solid fa-plus"></i> Agregar producto
    </button>
  </fieldset>

  <%= f.button :submit, "Crear orden", class: "btn btn-brand" %>
<% end %>
```

- [x] **Step 6: Create the new view**

Create `app/views/manager/orders/new.html.erb`:

```erb
<% content_for :title, "Nueva orden" %>

<div class="page-narrow">
  <h1 class="board__title">Nueva orden</h1>
  <%= render "form" %>
</div>
```

- [x] **Step 7: Create the Stimulus controller for add/remove rows**

Create `app/javascript/controllers/order_form_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

// Adds/removes nested order-item rows in the manager order form.
export default class extends Controller {
  static targets = ["lines", "template"]

  add(event) {
    event.preventDefault()
    const html = this.templateTarget.innerHTML.replace(/NEW_RECORD/g, new Date().getTime().toString())
    this.linesTarget.insertAdjacentHTML("beforeend", html)
  }

  remove(event) {
    event.preventDefault()
    const line = event.target.closest("[data-order-form-target='line']")
    const destroyField = line.querySelector("input[name*='_destroy']")
    if (destroyField) {
      destroyField.value = "1"
      line.style.display = "none"
    } else {
      line.remove()
    }
  }
}
```

- [x] **Step 8: Run it — expect pass**

Run: `bin/rails test test/integration/manager_orders_test.rb`
Expected: PASS.

- [x] **Step 9: Commit**

```bash
bin/rubocop -a
git add app/controllers/manager/orders_controller.rb app/views/manager/orders app/javascript/controllers/order_form_controller.js test/integration/manager_orders_test.rb
git commit -m "feat: manager new/create order with dynamic line items"
```

---

## Task 11: Manager — order detail (`show`) and assign rider (`update`)

**Files:**
- Modify: `app/controllers/manager/orders_controller.rb`
- Create: `app/views/manager/orders/show.html.erb`
- Modify: `test/integration/manager_orders_test.rb`

- [x] **Step 1: Write the failing test**

Add inside `test/integration/manager_orders_test.rb` (before the final `end`):

```ruby
  test "show displays the order and an assign-rider form when pending" do
    order = create_order(status: :pending)
    get manager_order_path(order)
    assert_response :success
    assert_select "select[name='order[rider_id]']"
  end

  test "update assigns a rider and moves the order to assigned" do
    order = create_order(status: :pending)
    patch manager_order_path(order), params: { order: { rider_id: @rider.id } }
    assert_redirected_to manager_order_path(order)
    assert order.reload.assigned?
    assert_equal @rider, order.rider
  end
```

- [x] **Step 2: Run it — expect failure**

Run: `bin/rails test test/integration/manager_orders_test.rb`
Expected: FAIL (no `show`/`update`).

- [x] **Step 3: Add show/update to the controller**

In `app/controllers/manager/orders_controller.rb`, add after `create`:

```ruby
  def show
    @order = Order.includes(order_items: :product).find(params[:id])
    @riders = User.rider.order(:email)
  end

  def update
    @order = Order.find(params[:id])
    rider = User.rider.find(params.dig(:order, :rider_id))
    if @order.assign_to!(rider)
      redirect_to manager_order_path(@order), notice: "Rider asignado."
    else
      redirect_to manager_order_path(@order), alert: "No se pudo asignar el rider."
    end
  end
```

- [x] **Step 4: Create the show view (detail + map + assign form)**

Create `app/views/manager/orders/show.html.erb`:

```erb
<% content_for :title, "Orden de #{@order.recipient_name}" %>

<div class="page-narrow order-detail">
  <%= link_to "← Volver al tablero", manager_orders_path, class: "order-detail__back" %>

  <header class="order-detail__head">
    <h1 class="board__title"><%= @order.recipient_name %></h1>
    <span class="status-pill status-pill--<%= @order.status %>">
      <span class="status-pill__dot"></span>
      <%= Manager::OrdersController::STATUS_LABELS[@order.status] %>
    </span>
  </header>

  <p class="order-detail__line"><i class="fa-solid fa-phone"></i> <%= @order.recipient_phone %></p>
  <p class="order-detail__line"><i class="fa-solid fa-location-dot"></i> <%= @order.address %></p>

  <% if @order.latitude && @order.longitude %>
    <div class="order-map"
         data-controller="map"
         data-map-api-key-value="<%= ENV["MAPBOX_API_KEY"] %>"
         data-map-lat-value="<%= @order.latitude %>"
         data-map-lng-value="<%= @order.longitude %>"></div>
  <% end %>

  <table class="order-items">
    <tbody>
      <% @order.order_items.each do |item| %>
        <tr>
          <td><%= item.quantity %>× <%= item.product.name %></td>
          <td class="order-items__amount">$<%= number_with_delimiter(item.subtotal) %></td>
        </tr>
      <% end %>
    </tbody>
    <tfoot>
      <tr><td>Total</td><td class="order-items__amount">$<%= number_with_delimiter(@order.total) %></td></tr>
    </tfoot>
  </table>

  <div class="order-detail__rider">
    <% if @order.rider %>
      <p>Asignada a <strong><%= @order.rider.email %></strong></p>
    <% elsif @order.pending? %>
      <%= simple_form_for [ :manager, @order ], method: :patch do |f| %>
        <%= f.association :rider, collection: @riders, label_method: :email, value_method: :id,
              include_blank: "Elegí un rider", label: "Asignar rider" %>
        <%= f.button :submit, "Asignar", class: "btn btn-brand" %>
      <% end %>
    <% end %>
  </div>
</div>
```

- [x] **Step 5: Run it — expect pass**

Run: `bin/rails test test/integration/manager_orders_test.rb`
Expected: PASS.

- [x] **Step 6: Commit**

```bash
bin/rubocop -a
git add app/controllers/manager/orders_controller.rb app/views/manager/orders/show.html.erb test/integration/manager_orders_test.rb
git commit -m "feat: manager order detail and assign-rider"
```

---

## Task 12: Rider — my deliveries (`index`)

**Files:**
- Modify: `app/controllers/rider/orders_controller.rb`
- Create: `app/views/rider/orders/index.html.erb`
- Create: `test/integration/rider_orders_test.rb`

- [x] **Step 1: Write the failing test**

Create `test/integration/rider_orders_test.rb`:

```ruby
require "test_helper"

class RiderOrdersTest < ActionDispatch::IntegrationTest
  setup do
    @rider = User.create!(email: "rider@example.com", password: "password123", role: :rider)
    @other_rider = User.create!(email: "other@example.com", password: "password123", role: :rider)
    @product = Product.create!(name: "Margarita", price: 150)
    sign_in @rider
  end

  def create_order(rider:, status: :assigned)
    order = Order.new(recipient_name: "Ana", recipient_phone: "55", address: "CDMX", rider: rider, status: status)
    order.order_items.build(product: @product, quantity: 1)
    order.save!
    order
  end

  test "index shows only my active deliveries" do
    create_order(rider: @rider, status: :assigned)
    create_order(rider: @other_rider, status: :assigned)
    get rider_orders_path
    assert_response :success
    # Two assigned orders exist but only the current rider's own one is listed.
    assert_select ".order-card", 1
  end
end
```

- [x] **Step 2: Run it — expect failure**

Run: `bin/rails test test/integration/rider_orders_test.rb`
Expected: FAIL (placeholder `index` renders no `.order-card`).

- [x] **Step 3: Implement the rider index**

Replace `app/controllers/rider/orders_controller.rb` with:

```ruby
class Rider::OrdersController < Rider::BaseController
  STATUS_LABELS = Manager::OrdersController::STATUS_LABELS

  def index
    orders = current_user.assigned_orders.includes(order_items: :product)
    @active_orders = orders.where(status: [ :assigned, :en_route ]).order(created_at: :asc)
    @delivered_orders = orders.delivered.order(updated_at: :desc)
  end
end
```

- [x] **Step 4: Create a rider card partial**

Create `app/views/rider/orders/_card.html.erb`:

```erb
<%= link_to rider_order_path(order), class: "order-card order-card--#{order.status}" do %>
  <div class="order-card__top">
    <span class="status-pill status-pill--<%= order.status %>">
      <span class="status-pill__dot"></span>
      <%= Rider::OrdersController::STATUS_LABELS[order.status] %>
    </span>
    <span class="order-card__time"><%= time_ago_in_words(order.created_at) %></span>
  </div>
  <div class="order-card__name"><%= order.recipient_name %></div>
  <div class="order-card__addr">
    <i class="fa-solid fa-location-dot"></i> <%= order.address %>
  </div>
  <div class="order-card__items">
    <%= order.order_items.map { |i| "#{i.quantity}× #{i.product.name}" }.join(" · ") %>
  </div>
  <hr class="order-card__sep">
  <div class="order-card__bottom">
    <span class="order-card__unassigned"><%= order.recipient_phone %></span>
    <span class="order-card__total">$<%= number_with_delimiter(order.total) %></span>
  </div>
<% end %>
```

- [x] **Step 5: Create the rider index view**

Create `app/views/rider/orders/index.html.erb`:

```erb
<% content_for :title, "Mis entregas" %>

<div class="page-narrow">
  <h1 class="board__title">Mis entregas</h1>

  <% if @active_orders.any? %>
    <div class="rider-list">
      <%= render partial: "card", collection: @active_orders, as: :order %>
    </div>
  <% else %>
    <p class="empty-state">No tienes entregas activas. 🎉</p>
  <% end %>

  <% if @delivered_orders.any? %>
    <h2 class="board__sub">Entregadas</h2>
    <div class="rider-list rider-list--muted">
      <%= render partial: "card", collection: @delivered_orders, as: :order %>
    </div>
  <% end %>
</div>
```

- [x] **Step 6: Run it — expect pass**

Run: `bin/rails test test/integration/rider_orders_test.rb`
Expected: PASS (only 1 `.order-card` — the rider's own active order).

- [x] **Step 7: Commit**

```bash
bin/rubocop -a
git add app/controllers/rider/orders_controller.rb app/views/rider/orders test/integration/rider_orders_test.rb
git commit -m "feat: rider my-deliveries index scoped to current rider"
```

---

## Task 13: Rider — delivery detail (`show`) and advance status (`update`)

**Files:**
- Modify: `app/controllers/rider/orders_controller.rb`
- Create: `app/views/rider/orders/show.html.erb`
- Modify: `test/integration/rider_orders_test.rb`

- [x] **Step 1: Write the failing test**

Add inside `test/integration/rider_orders_test.rb` (before the final `end`):

```ruby
  test "rider advances assigned -> en_route -> delivered on own order" do
    order = create_order(rider: @rider, status: :assigned)

    patch rider_order_path(order), params: { transition: "en_route" }
    assert order.reload.en_route?

    patch rider_order_path(order), params: { transition: "delivered" }
    assert order.reload.delivered?
    assert_redirected_to rider_orders_path
  end

  test "rider cannot view another rider's order" do
    theirs = create_order(rider: @other_rider, status: :assigned)
    get rider_order_path(theirs)
    assert_response :not_found
  end

  test "rider cannot advance another rider's order" do
    theirs = create_order(rider: @other_rider, status: :assigned)
    patch rider_order_path(theirs), params: { transition: "en_route" }
    assert_response :not_found
    assert theirs.reload.assigned?
  end
```

- [x] **Step 2: Run it — expect failure**

Run: `bin/rails test test/integration/rider_orders_test.rb`
Expected: FAIL (no `show`/`update`).

- [x] **Step 3: Add show/update to the rider controller**

In `app/controllers/rider/orders_controller.rb`, add after `index`:

```ruby
  def show
    @order = current_user.assigned_orders.includes(order_items: :product).find(params[:id])
  end

  def update
    @order = current_user.assigned_orders.find(params[:id])
    advance(@order, params[:transition])
    redirect_to rider_orders_path, notice: "Estado actualizado."
  end

  private

  def advance(order, transition)
    case transition
    when "en_route" then order.mark_en_route!
    when "delivered" then order.mark_delivered!
    end
  end
```

(`current_user.assigned_orders.find` scopes to the rider's own orders, so another rider's id raises `ActiveRecord::RecordNotFound` → 404, satisfying the authorization tests.)

- [x] **Step 4: Create the rider show view**

Create `app/views/rider/orders/show.html.erb`:

```erb
<% content_for :title, "Entrega de #{@order.recipient_name}" %>

<div class="page-narrow order-detail">
  <%= link_to "← Mis entregas", rider_orders_path, class: "order-detail__back" %>

  <header class="order-detail__head">
    <h1 class="board__title"><%= @order.recipient_name %></h1>
    <span class="status-pill status-pill--<%= @order.status %>">
      <span class="status-pill__dot"></span>
      <%= Rider::OrdersController::STATUS_LABELS[@order.status] %>
    </span>
  </header>

  <p class="order-detail__line"><i class="fa-solid fa-phone"></i> <%= @order.recipient_phone %></p>
  <p class="order-detail__line"><i class="fa-solid fa-location-dot"></i> <%= @order.address %></p>

  <% if @order.latitude && @order.longitude %>
    <div class="order-map"
         data-controller="map"
         data-map-api-key-value="<%= ENV["MAPBOX_API_KEY"] %>"
         data-map-lat-value="<%= @order.latitude %>"
         data-map-lng-value="<%= @order.longitude %>"></div>
  <% end %>

  <table class="order-items">
    <tbody>
      <% @order.order_items.each do |item| %>
        <tr><td><%= item.quantity %>× <%= item.product.name %></td>
            <td class="order-items__amount">$<%= number_with_delimiter(item.subtotal) %></td></tr>
      <% end %>
    </tbody>
    <tfoot>
      <tr><td>Total</td><td class="order-items__amount">$<%= number_with_delimiter(@order.total) %></td></tr>
    </tfoot>
  </table>

  <div class="order-detail__actions">
    <% if @order.assigned? %>
      <%= button_to "Marcar en camino", rider_order_path(@order), method: :patch,
            params: { transition: "en_route" }, class: "btn btn-brand" %>
    <% elsif @order.en_route? %>
      <%= button_to "Marcar entregada", rider_order_path(@order), method: :patch,
            params: { transition: "delivered" }, class: "btn btn-brand" %>
    <% else %>
      <p class="empty-state">Entrega completada ✓</p>
    <% end %>
  </div>
</div>
```

- [x] **Step 5: Run it — expect pass**

Run: `bin/rails test test/integration/rider_orders_test.rb`
Expected: PASS.

- [x] **Step 6: Run the full suite**

Run: `bin/rails test`
Expected: PASS (models + all integration tests).

- [x] **Step 7: Commit**

```bash
bin/rubocop -a
git add app/controllers/rider/orders_controller.rb app/views/rider/orders/show.html.erb test/integration/rider_orders_test.rb
git commit -m "feat: rider delivery detail and status advancement"
```

---

## Task 14: Mapbox map on order detail pages

This task has no automated test (it renders a JS map); it is **verified manually**.

**Files:**
- Modify: `config/importmap.rb`
- Create: `app/javascript/controllers/map_controller.js`
- Modify: `app/views/layouts/application.html.erb`
- Modify: `.env` (local only — gitignored)

- [x] **Step 1: Pin Mapbox GL JS**

Run: `bin/importmap pin mapbox-gl`
Expected: a `pin "mapbox-gl", to: "https://ga.jspm.io/npm:mapbox-gl@..."` line is added to `config/importmap.rb`.

- [x] **Step 2: Add the Mapbox stylesheet to the layout `<head>`**

In `app/views/layouts/application.html.erb`, add directly above the `<%= stylesheet_link_tag ... %>` line:

```erb
    <link href="https://api.mapbox.com/mapbox-gl-js/v3.7.0/mapbox-gl.css" rel="stylesheet">
```

- [x] **Step 3: Create the map Stimulus controller**

Create `app/javascript/controllers/map_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"
import mapboxgl from "mapbox-gl"

// Renders a single delivery-destination marker on a Mapbox map.
export default class extends Controller {
  static values = { apiKey: String, lat: Number, lng: Number }

  connect() {
    mapboxgl.accessToken = this.apiKeyValue
    this.map = new mapboxgl.Map({
      container: this.element,
      style: "mapbox://styles/mapbox/streets-v12",
      center: [this.lngValue, this.latValue],
      zoom: 14
    })
    new mapboxgl.Marker()
      .setLngLat([this.lngValue, this.latValue])
      .addTo(this.map)
  }

  disconnect() {
    this.map?.remove()
  }
}
```

- [x] **Step 4: Add your Mapbox key locally**

Add to `.env` (this file is gitignored — do not commit it):

```
MAPBOX_API_KEY=pk.your_mapbox_public_token_here
```

(Get a free public token at https://account.mapbox.com/access-tokens/. The same token powers both geocoding and map tiles.)

- [x] **Step 5: Manual verification**

Run: `bin/rails db:seed` then `bin/dev`
- Sign in as the seeded manager, open any order's detail page → a map with a marker at the delivery address renders.
- Open the browser console → no JS import errors for `mapbox-gl`.

Expected: map renders with a marker. If the jspm pin fails to load, fall back to pinning the CDN ESM build: `pin "mapbox-gl", to: "https://api.mapbox.com/mapbox-gl-js/v3.7.0/mapbox-gl.js"` and reload.

- [x] **Step 6: Verify the suite still passes (no key needed in tests)**

Run: `bin/rails test`
Expected: PASS (tests use the geocoder test stub; the map only renders client-side).

- [x] **Step 7: Commit**

```bash
bin/rubocop -a
git add config/importmap.rb app/javascript/controllers/map_controller.js app/views/layouts/application.html.erb
git commit -m "feat: render delivery location on a Mapbox map"
```

---

## Task 15: Design tokens — colors, fonts, Bootstrap variables

**Files:**
- Modify: `app/assets/stylesheets/config/_colors.scss`
- Modify: `app/assets/stylesheets/config/_fonts.scss`
- Modify: `app/assets/stylesheets/config/_bootstrap_variables.scss`

Visual reference for exact values: the approved mockup `.superpowers/brainstorm/9705-1779610060/content/kanban-final.html`.

- [x] **Step 1: Define the color tokens**

Replace `app/assets/stylesheets/config/_colors.scss` with:

```scss
// PizzApp design tokens — brand "verde albahaca"
$brand:       #16A34A;
$bg:          #EFEFF3;
$panel:       #FFFFFF;
$ink:         #191B22;
$ink-2:       #4B5160;
$muted:       #8A8F9C;
$line:        #E7E7EE;

// Status accents (dot / pill background / pill text)
$pending:     #D99A2B;  $pending-bg:  #FBF0D8;  $pending-tx:  #8A5B12;
$assigned:    #5B72E8;  $assigned-bg: #E9EBFB;  $assigned-tx: #3742A6;
$en-route:    #F2683C;  $en-route-bg: #FCE7DD;  $en-route-tx: #B0441F;
$delivered:   #2FA968;  $delivered-bg:#DFF3E7;  $delivered-tx:#1A7546;

// Keep a couple of legacy aliases used by the template's partials
$light-gray:  $bg;
$gray:        $ink;
```

- [x] **Step 2: Define the fonts**

Replace `app/assets/stylesheets/config/_fonts.scss` with:

```scss
// Import Google fonts: Inter (body) + Plus Jakarta Sans (headings)
@import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=Plus+Jakarta+Sans:wght@600;700;800&display=swap');

$body-font:    "Inter", "Helvetica", sans-serif;
$headers-font: "Plus Jakarta Sans", "Inter", sans-serif;
```

- [x] **Step 3: Map tokens onto Bootstrap variables**

In `app/assets/stylesheets/config/_bootstrap_variables.scss`, update the "General style" and "Colors" sections to:

```scss
// General style
$font-family-sans-serif: $body-font;
$headings-font-family:   $headers-font;
$body-bg:                $bg;
$font-size-base:         1rem;

// Colors
$body-color: $ink;
$primary:    $brand;
$success:    $delivered;
$info:       $assigned;
$danger:     $en-route;
$warning:    $pending;
```

Leave the border-radius block below it as-is.

- [x] **Step 4: Verify SCSS compiles**

Run: `bin/rails assets:precompile 2>&1 | tail -5` (or load any page with `bin/dev`).
Expected: no Sass errors.

- [x] **Step 5: Commit**

```bash
git add app/assets/stylesheets/config
git commit -m "style: add PizzApp design tokens (basil-green brand, Inter/Jakarta)"
```

---

## Task 16: App shell — sidebar layout

**Files:**
- Modify: `app/views/layouts/application.html.erb`
- Create: `app/views/shared/_sidebar.html.erb`
- Create: `app/assets/stylesheets/components/_app_shell.scss`
- Modify: `app/assets/stylesheets/components/_index.scss`

- [x] **Step 1: Replace the navbar render with a sidebar shell in the layout**

In `app/views/layouts/application.html.erb`, replace the `<body>` block:

```erb
  <body>
    <% if user_signed_in? %>
      <div class="app-shell">
        <%= render "shared/sidebar" %>
        <main class="app-shell__main">
          <%= render "shared/flashes" %>
          <%= yield %>
        </main>
      </div>
    <% else %>
      <%= render "shared/flashes" %>
      <%= yield %>
    <% end %>
  </body>
```

- [x] **Step 2: Create the sidebar partial**

Create `app/views/shared/_sidebar.html.erb`:

```erb
<aside class="sidebar">
  <div class="sidebar__brand">
    <span class="sidebar__logo">🍕</span> PizzApp
  </div>

  <nav class="sidebar__nav">
    <% if current_user.manager? %>
      <%= link_to manager_orders_path, class: "sidebar__link #{'is-active' if controller_path == 'manager/orders'}" do %>
        <i class="fa-solid fa-table-columns"></i> Tablero
      <% end %>
      <%= link_to new_manager_order_path, class: "sidebar__link" do %>
        <i class="fa-solid fa-plus"></i> Nueva orden
      <% end %>
    <% else %>
      <%= link_to rider_orders_path, class: "sidebar__link #{'is-active' if controller_path == 'rider/orders'}" do %>
        <i class="fa-solid fa-box"></i> Mis entregas
      <% end %>
    <% end %>
  </nav>

  <div class="sidebar__foot">
    <div class="sidebar__user">
      <div class="sidebar__avatar"><%= current_user.email.first(2).upcase %></div>
      <div>
        <div class="sidebar__name"><%= current_user.email.split("@").first %></div>
        <div class="sidebar__role"><%= current_user.manager? ? "Manager" : "Rider" %></div>
      </div>
    </div>
    <%= link_to "Salir", destroy_user_session_path, data: { turbo_method: :delete }, class: "sidebar__logout" %>
  </div>
</aside>
```

- [x] **Step 3: Style the app shell + sidebar**

Create `app/assets/stylesheets/components/_app_shell.scss`:

```scss
.app-shell {
  display: flex;
  min-height: 100vh;
  padding: 14px;
  gap: 14px;
  background:
    radial-gradient(1100px 480px at 100% -12%, rgba($brand, 0.08), transparent 65%),
    radial-gradient(820px 420px at -8% 116%, rgba($assigned, 0.07), transparent 62%),
    $bg;
}

.app-shell__main { flex: 1; min-width: 0; }

.sidebar {
  width: 228px;
  flex-shrink: 0;
  display: flex;
  flex-direction: column;
  padding: 22px 15px;
  border-radius: 22px;
  background: linear-gradient(180deg, #1C1F27, #121319);
  color: #C0C5D1;
  box-shadow: 0 2px 4px rgba(20, 22, 30, 0.05), 0 12px 28px rgba(20, 22, 30, 0.10);

  &__brand {
    display: flex; align-items: center; gap: 11px;
    color: #fff; font-family: $headers-font; font-weight: 800; font-size: 19px;
    padding: 2px 8px 26px;
  }
  &__logo {
    width: 36px; height: 36px; border-radius: 12px; display: grid; place-items: center;
    background: linear-gradient(140deg, $brand, lighten($brand, 18%));
    box-shadow: 0 8px 20px rgba($brand, 0.45);
  }
  &__nav { display: flex; flex-direction: column; gap: 4px; }
  &__link {
    display: flex; align-items: center; gap: 12px;
    padding: 11px 13px; border-radius: 13px;
    color: #969CAA; text-decoration: none; font-weight: 500; font-size: 14px;
    transition: background 0.18s, color 0.18s;
    &:hover { color: #fff; background: rgba(255, 255, 255, 0.05); }
    &.is-active { color: #fff; background: rgba($brand, 0.18); }
  }
  &__foot { margin-top: auto; }
  &__user {
    display: flex; align-items: center; gap: 11px;
    padding: 11px; border-radius: 15px;
    background: rgba(255, 255, 255, 0.05); border: 1px solid rgba(255, 255, 255, 0.06);
  }
  &__avatar {
    width: 34px; height: 34px; border-radius: 11px; display: grid; place-items: center;
    color: #fff; font-weight: 700; font-size: 12px;
    background: linear-gradient(135deg, #5B72E8, #9B5BE8);
  }
  &__name { color: #fff; font-size: 13px; font-weight: 600; }
  &__role { color: #7F8694; font-size: 11px; }
  &__logout {
    display: block; margin-top: 12px; text-align: center;
    color: #969CAA; font-size: 13px; text-decoration: none;
    &:hover { color: #fff; }
  }
}
```

- [x] **Step 4: Import the new component**

In `app/assets/stylesheets/components/_index.scss`, add at the top of the imports:

```scss
@import "app_shell";
```

- [x] **Step 5: Verify it renders**

Run: `bin/dev`, sign in → the sidebar shell appears with the correct links for the role.
Expected: sidebar shows "Tablero/Nueva orden" for a manager, "Mis entregas" for a rider.

- [x] **Step 6: Commit**

```bash
git add app/views/layouts/application.html.erb app/views/shared/_sidebar.html.erb app/assets/stylesheets/components/_app_shell.scss app/assets/stylesheets/components/_index.scss
git commit -m "feat: sidebar app shell for signed-in users"
```

---

## Task 17: Kanban, order-card, status-pill and order-detail styles

**Files:**
- Create: `app/assets/stylesheets/components/_status_pill.scss`
- Create: `app/assets/stylesheets/components/_order_card.scss`
- Create: `app/assets/stylesheets/components/_kanban.scss`
- Modify: `app/assets/stylesheets/components/_index.scss`
- Create: `app/assets/stylesheets/pages/_orders.scss`
- Modify: `app/assets/stylesheets/pages/_index.scss`

Visual reference: `.superpowers/brainstorm/9705-1779610060/content/kanban-final.html`.

- [x] **Step 1: Status pill**

Create `app/assets/stylesheets/components/_status_pill.scss`:

```scss
.status-pill {
  display: inline-flex; align-items: center; gap: 6px;
  font-size: 11px; font-weight: 700; letter-spacing: 0.1px;
  padding: 5px 11px; border-radius: 9px;

  &__dot { width: 6px; height: 6px; border-radius: 50%; background: currentColor; }

  &--pending   { background: $pending-bg;   color: $pending-tx;   box-shadow: inset 0 0 0 1px rgba($pending, 0.22); }
  &--assigned  { background: $assigned-bg;  color: $assigned-tx;  box-shadow: inset 0 0 0 1px rgba($assigned, 0.22); }
  &--en_route  { background: $en-route-bg;  color: $en-route-tx;  box-shadow: inset 0 0 0 1px rgba($en-route, 0.22); }
  &--delivered { background: $delivered-bg; color: $delivered-tx; box-shadow: inset 0 0 0 1px rgba($delivered, 0.22); }
}
```

- [x] **Step 2: Order card**

Create `app/assets/stylesheets/components/_order_card.scss`:

```scss
.order-card {
  position: relative; display: block;
  background: $panel; border: 1px solid $line; border-radius: 18px;
  padding: 15px 16px; margin: 0 2px 11px;
  box-shadow: 0 1px 1px rgba(20, 22, 30, 0.04), 0 2px 4px rgba(20, 22, 30, 0.04);
  color: $ink; text-decoration: none;
  transition: transform 0.16s, box-shadow 0.16s, border-color 0.16s;

  &::before {
    content: ""; position: absolute; left: 0; top: 0; bottom: 0; width: 3px;
    border-radius: 18px 0 0 18px; background: $muted;
  }
  &--pending::before   { background: $pending; }
  &--assigned::before  { background: $assigned; }
  &--en_route::before  { background: $en-route; }
  &--delivered::before { background: $delivered; }
  &--delivered { opacity: 0.9; }

  &:hover {
    transform: translateY(-3px);
    box-shadow: 0 2px 4px rgba(20, 22, 30, 0.05), 0 12px 28px rgba(20, 22, 30, 0.10);
  }

  &__top { display: flex; align-items: center; justify-content: space-between; margin-bottom: 11px; }
  &__time { font-size: 11px; color: #ABB0BA; font-weight: 500; }
  &__name { font-family: $headers-font; font-size: 15.5px; font-weight: 700; letter-spacing: -0.3px; }
  &__addr {
    display: flex; align-items: center; gap: 7px;
    font-size: 12.5px; color: $muted; margin: 7px 0 9px;
    i { color: #AEB3BD; }
  }
  &__items { font-size: 12.5px; color: $ink-2; font-weight: 500; }
  &__sep { border: 0; height: 1px; background: $line; margin: 13px 0 12px; }
  &__bottom { display: flex; align-items: center; justify-content: space-between; }
  &__rider { font-size: 13px; font-weight: 600; }
  &__unassigned { font-size: 12.5px; color: #AEB3BD; font-style: italic; }
  &__total { font-family: $headers-font; font-size: 15.5px; font-weight: 800; letter-spacing: -0.4px; }
}
```

- [x] **Step 3: Kanban layout**

Create `app/assets/stylesheets/components/_kanban.scss`:

```scss
.kanban {
  display: grid; grid-template-columns: repeat(4, 1fr); gap: 16px; align-items: start;
}

.kanban-column {
  border-radius: 20px; padding: 6px 8px 8px;
  background: linear-gradient(180deg, rgba(255, 255, 255, 0.55), rgba(255, 255, 255, 0.2));
  border: 1px solid rgba(255, 255, 255, 0.6);

  &__head { display: flex; align-items: center; gap: 9px; padding: 12px 10px 13px; }
  &__dot { width: 8px; height: 8px; border-radius: 50%; }
  &--pending   .kanban-column__dot { background: $pending; }
  &--assigned  .kanban-column__dot { background: $assigned; }
  &--en_route  .kanban-column__dot { background: $en-route; }
  &--delivered .kanban-column__dot { background: $delivered; }
  &__title { font-family: $headers-font; font-size: 13.5px; font-weight: 700; color: $ink-2; }
  &__count {
    margin-left: auto; font-size: 11.5px; font-weight: 700; color: $ink-2;
    background: #fff; border: 1px solid $line; border-radius: 8px;
    min-width: 24px; text-align: center; padding: 2px 7px;
  }
}

@media (max-width: 900px) {
  .kanban { grid-template-columns: 1fr 1fr; }
}
```

- [x] **Step 4: Board header + order pages**

Create `app/assets/stylesheets/pages/_orders.scss`:

```scss
.board__top { display: flex; align-items: center; justify-content: space-between; margin-bottom: 18px; }
.board__title { font-family: $headers-font; font-size: 23px; font-weight: 800; letter-spacing: -0.6px; }
.board__sub { font-size: 13px; color: $muted; margin-top: 4px; }

.btn-brand {
  background: $brand; border: none; color: #fff; font-weight: 600; border-radius: 13px;
  padding: 11px 17px;
  box-shadow: 0 8px 18px rgba($brand, 0.30);
  &:hover { background: darken($brand, 5%); color: #fff; }
}
.btn-outline-brand {
  background: rgba($brand, 0.07); border: 1px dashed rgba($brand, 0.45);
  color: $brand; font-weight: 700; border-radius: 10px; padding: 7px 13px;
  &:hover { background: rgba($brand, 0.13); }
}

.page-narrow { max-width: 640px; }

.order-form {
  &__items { border: 0; margin: 18px 0; }
  legend { font-size: 13px; font-weight: 700; color: $ink-2; }
}
.order-line {
  display: flex; gap: 10px; align-items: flex-start; margin-bottom: 10px;
  &__qty { max-width: 90px; }
  &__remove { border: 0; background: transparent; color: $muted; cursor: pointer; padding: 10px; }
}

.order-detail {
  &__back { font-size: 13px; color: $muted; text-decoration: none; }
  &__head { display: flex; align-items: center; gap: 12px; margin: 8px 0 14px; }
  &__line { color: $ink-2; i { color: $muted; margin-right: 6px; } }
  &__rider, &__actions { margin-top: 18px; }
}

.order-map {
  height: 260px; border-radius: 16px; overflow: hidden; margin: 14px 0;
  border: 1px solid $line;
}

.order-items {
  width: 100%; margin: 16px 0; border-collapse: collapse;
  td { padding: 8px 0; border-bottom: 1px solid $line; }
  &__amount { text-align: right; font-weight: 600; }
  tfoot td { font-weight: 800; border-bottom: 0; }
}

.rider-list { display: grid; gap: 0; max-width: 460px; }
.rider-list--muted { opacity: 0.85; }
.empty-state { color: $muted; padding: 20px 0; }
```

- [x] **Step 5: Register the new partials**

In `app/assets/stylesheets/components/_index.scss`, add to the imports:

```scss
@import "status_pill";
@import "order_card";
@import "kanban";
```

In `app/assets/stylesheets/pages/_index.scss`, add:

```scss
@import "orders";
```

- [x] **Step 6: Verify the board renders correctly**

Run: `bin/dev`, sign in as the seeded manager → the kanban renders with four styled columns, colored status pills, and hover-lifting cards matching the mockup.
Expected: visual match to `.superpowers/brainstorm/9705-1779610060/content/kanban-final.html`.

- [x] **Step 7: Commit**

```bash
git add app/assets/stylesheets
git commit -m "style: kanban board, order cards, status pills and order detail"
```

---

## Task 18: Seeds and full CI

**Files:**
- Modify: `db/seeds.rb`

- [x] **Step 1: Write the seeds**

Replace `db/seeds.rb` with:

```ruby
# Idempotent seeds for PizzApp.
puts "Clearing existing data…"
OrderItem.delete_all
Order.delete_all
Product.delete_all
User.delete_all

puts "Creating users…"
manager = User.create!(email: "manager@pizzapp.test", password: "password123", role: :manager)
riders = [
  User.create!(email: "pedro@pizzapp.test", password: "password123", role: :rider),
  User.create!(email: "jorge@pizzapp.test", password: "password123", role: :rider)
]

puts "Creating products…"
products = {
  margarita: Product.create!(name: "Margarita", price: 150),
  pepperoni: Product.create!(name: "Pepperoni", price: 180),
  hawaiana:  Product.create!(name: "Hawaiana", price: 175),
  coca:      Product.create!(name: "Coca-Cola", price: 30),
  agua:      Product.create!(name: "Agua", price: 20)
}

puts "Creating orders…"
samples = [
  { name: "Ana Gómez",  phone: "5512345678", address: "Av. Álvaro Obregón 64, Roma Norte, CDMX",
    status: :pending,  rider: nil,        items: [ [ :margarita, 1 ], [ :coca, 1 ] ] },
  { name: "Carla Ruiz", phone: "5512345679", address: "Calle Orizaba 12, Roma Norte, CDMX",
    status: :pending,  rider: nil,        items: [ [ :pepperoni, 2 ], [ :agua, 1 ] ] },
  { name: "Beto Salas", phone: "5512345680", address: "Av. Insurgentes Sur 300, CDMX",
    status: :assigned, rider: riders[0],  items: [ [ :hawaiana, 1 ], [ :margarita, 1 ] ] },
  { name: "Luis Mora",  phone: "5512345681", address: "Córdoba 210, Roma Norte, CDMX",
    status: :en_route, rider: riders[0],  items: [ [ :pepperoni, 3 ], [ :coca, 1 ] ] },
  { name: "María Díaz", phone: "5512345682", address: "Colima 143, Roma Norte, CDMX",
    status: :delivered, rider: riders[1], items: [ [ :hawaiana, 1 ], [ :agua, 1 ] ] }
]

samples.each do |s|
  order = Order.new(recipient_name: s[:name], recipient_phone: s[:phone], address: s[:address],
                    status: s[:status], rider: s[:rider])
  s[:items].each { |key, qty| order.order_items.build(product: products[key], quantity: qty) }
  order.save!
end

puts "Done: #{User.count} users, #{Product.count} products, #{Order.count} orders."
```

(Geocoding runs against Mapbox during seeding, so `MAPBOX_API_KEY` must be set in `.env`. If it is missing, orders still save but without coordinates — the map simply won't render for them.)

- [x] **Step 2: Run the seeds**

Run: `bin/rails db:seed:replant`
Expected: prints the final counts, no errors.

- [x] **Step 3: Run the full test suite**

Run: `bin/rails test`
Expected: PASS (all model + integration tests).

- [x] **Step 4: Run the full CI gate**

Run: `bin/ci`
Expected: RuboCop clean, security scanners clean, tests green, seeds replant succeeds. Fix anything that fails, then re-run.

- [x] **Step 5: Commit**

```bash
git add db/seeds.rb
git commit -m "chore: seed PizzApp with users, menu and sample orders"
```

---

## Final verification checklist

- [x] `bin/ci` passes end-to-end.
- [x] Manager flow: sign in → kanban → "Nueva orden" with multiple line items → order detail → assign rider.
- [x] Rider flow: sign in → "Mis entregas" (only own) → open delivery → "Marcar en camino" → "Marcar entregada".
- [x] A rider visiting another rider's order URL gets a 404; a rider visiting `/manager/orders` is redirected to root.
- [x] Order detail shows a Mapbox map at the delivery address (requires `MAPBOX_API_KEY`).
- [x] The board visually matches `.superpowers/brainstorm/9705-1779610060/content/kanban-final.html`.
```
