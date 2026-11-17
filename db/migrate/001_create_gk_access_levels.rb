# frozen_string_literal: true

# Merged at 1.00.000: the final state of gk_access_levels.
# Information levels as data with a rank (a higher rank is more restricted). The three defaults are made here with
# steps of 100, so that levels can be put between and above them. A level in use is never removed, only closed for
# new things. The name is written in one language; a default level with no name takes its name from the locales.
# The first migration's down runs last at redmine:plugins:migrate NAME=gk_access VERSION=0: it also takes away the
# plugin's row in core's settings. The plugin keeps nothing in the persons' preferences.
class CreateGkAccessLevels < ActiveRecord::Migration[6.1]
  DEFAULTS = [%w[open 0], %w[internal 100], %w[sensitive 200]].freeze

  def up
    create_table "gk_access_levels" do |t|
      t.string "key", limit: 40, null: false
      t.integer "rank", null: false
      t.string "name", limit: 120
      t.boolean "closed", default: false, null: false
      t.datetime "created_at", null: false, precision: 6
      t.datetime "updated_at", null: false, precision: 6
      t.index ["key"], name: "index_gk_access_levels_key", unique: true
      t.index ["rank"], name: "index_gk_access_levels_rank", unique: true
    end

    Level.reset_column_information
    DEFAULTS.each { |key, rank| Level.create!(key: key, rank: rank.to_i, closed: false) }
  end

  # The migration's own model, so that a later change to the plugin's model does not change what this one makes
  class Level < ActiveRecord::Base
    self.table_name = 'gk_access_levels'
  end

  def down
    drop_table :gk_access_levels
    Setting.where(name: 'plugin_gk_access').delete_all
  end
end
