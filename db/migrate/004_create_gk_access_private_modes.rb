# frozen_string_literal: true

# Merged at 1.00.000: the final state of gk_access_private_modes.
# Which kind of Private holds: as in Redmine (the default) or strict, for private issues and private notes each. The
# row without a project is the instance's choice; a row with a project is that project's own, which can only be
# stricter than the instance's. Every change is an event in records with this row as its target.
class CreateGkAccessPrivateModes < ActiveRecord::Migration[6.1]
  def up
    create_table "gk_access_private_modes" do |t|
      t.integer "project_id"
      t.boolean "issues_strict", default: false, null: false
      t.boolean "notes_strict", default: false, null: false
      t.datetime "updated_at", precision: nil, null: false
    end
    add_index "gk_access_private_modes", ["project_id"], name: "index_gk_access_private_modes_on_project_id", unique: true
  end

  def down
    drop_table :gk_access_private_modes
  end
end
