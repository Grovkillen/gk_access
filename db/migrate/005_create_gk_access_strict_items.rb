# frozen_string_literal: true

# Merged at 1.00.000: the final state of gk_access_strict_items.
# The private issues and private notes that are strictly private. A thing is marked when it becomes private where
# strict holds, or when strict is chosen where it already was private, and stays strict after that, also when the
# instance or the project goes back to Private as in Redmine or the issue moves: it never becomes ordinary private
# again. Only its author ends it, by making it not private. The token is
# the thing's anonymous identity, drawn at random when it is marked: the only name an administrator, the log or an
# annulment ever sees for it.
class CreateGkAccessStrictItems < ActiveRecord::Migration[6.1]
  def up
    create_table "gk_access_strict_items" do |t|
      t.string "item_type", limit: 30, null: false
      t.integer "item_id", null: false
      t.string "token", limit: 20, null: false
      t.datetime "created_at", precision: nil, null: false
    end
    add_index "gk_access_strict_items", ["item_type", "item_id"], name: "index_gk_access_strict_items_on_item", unique: true
    add_index "gk_access_strict_items", ["token"], name: "index_gk_access_strict_items_on_token", unique: true
  end

  def down
    drop_table :gk_access_strict_items
  end
end
