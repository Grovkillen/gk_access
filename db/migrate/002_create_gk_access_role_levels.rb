# frozen_string_literal: true

# Merged at 1.00.000: the final state of gk_access_role_levels.
# A role's ceiling: the highest level the role sees. Without a row the ceiling is the lowest level. One row per role,
# the builtin roles (Non member, Anonymous) included. Core's tables get no columns (the row is the plugin's own).
class CreateGkAccessRoleLevels < ActiveRecord::Migration[6.1]
  def up
    create_table "gk_access_role_levels" do |t|
      t.integer "role_id", null: false
      t.integer "level_id", null: false
      t.datetime "created_at", null: false, precision: 6
      t.datetime "updated_at", null: false, precision: 6
      t.index ["level_id"], name: "index_gk_access_role_levels_level"
      t.index ["role_id"], name: "index_gk_access_role_levels_role", unique: true
    end
  end

  def down
    drop_table :gk_access_role_levels
  end
end
