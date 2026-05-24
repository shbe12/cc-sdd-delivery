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
