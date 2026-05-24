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
