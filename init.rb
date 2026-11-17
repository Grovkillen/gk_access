# frozen_string_literal: true
# Depends on: gk_records 1.06.000 or later, gk_core_stuff and gk_gui_stuff 1.05.000 or later required; optional
# gk_compat, gk_fields, gk_people, gk_retention, gk_scenarios. Without gk_gui_stuff the pages, the menu, the REST API,
# the explanation by Private and what access registers in other plugins to be drawn (the appearance setting, the
# translations, the tab Private) are closed (GkAccess.gui?, gate.rb); the settings page says so.
# A gate never closes a protection or a trace: the core patches for strictly private, the marking and the questions
# about levels work all the same, the targets and the event kinds are registered in gk_records all the same, so that
# the events are written, the permissions stay registered, and the migrations run all the same.
# gk_access: the core layer for information levels and Private. The register of levels with a rank, every role's
# ceiling, the question whether a person sees a level (GkAccess.sees?), and Private for core's private issues and
# private notes: as in Redmine, or strict where the instance or a project chooses it, with the kind and who sees it
# shown to the person. Without gk_records no level, ceiling or Private changes. The dependencies are not declared with
# requires_redmine_plugin: Redmine loads plugins in alphabetical order (gk_access before gk_records) and checks at
# registration.

# The gate to GK GUI Stuff, first, so that every file below may ask it
require_relative 'extensions/gk_access/gate'
require_relative 'extensions/gk_access/core'
require_relative 'extensions/gk_access/private'
require_relative 'extensions/gk_access/hooks'
require_relative 'extensions/gk_access/patches'

Redmine::Plugin.register :gk_access do
  name        'GK Access'
  author      'Jimmy Westberg'
  description 'Information levels with a rank, a ceiling per role, and Private as in Redmine or strict'
  version     '1.00.000'
  requires_redmine version_or_higher: '6.0.0'
  # Configure: about the plugin and the change log; the settings themselves are on Administration > Levels
  settings default: {}, partial: 'settings/gk_access_settings'

  # The permissions, registered whatever the gate says, so that no role loses one while the gate is closed (core's
  # role form lists only the permissions that are registered and writes the whole list). Closed, they open nothing:
  # the controllers answer 404. A project's own kind of Private (the tab Private in its settings): whoever has it makes
  # the project stricter. projects: :settings as core's own settings permissions, so that a role with only this one
  # reaches the project's settings (core shows only the tabs a role may use). Not in a project module: Private holds
  # whatever the modules. The last two are OAuth scopes only (a role grants nothing with them): reading and changing
  # the levels, the ceilings and Private over REST (who may is still the admin flag, or Manage Private in a project).
  permission :manage_gk_access_private, { projects: :settings, gk_access_private_modes: %i[show update] }, require: :member
  permission :gk_access_api_read, {}, require: :loggedin
  permission :gk_access_api_manage, {}, require: :loggedin

  menu :admin_menu, :gk_access_levels, { controller: 'gk_access_levels', action: 'index' },
       caption: :label_gk_access_levels, icon: 'lock', html: { class: 'icon' }, if: proc { GkAccess.gui? }
end

# The protection, whatever the gate says (a gate never closes a protection): the core patches (patches.rb), applied
# here and again on every reload
GkAccess::Patches.apply!

# The view listeners are registered when their classes are defined, again after a reload (Redmine::Hook lives in
# core's lib/).
Redmine::Hook.add_listener(GkAccess::Hooks) unless Redmine::Hook.listeners.any?(GkAccess::Hooks)
Redmine::Hook.add_listener(GkAccess::RefusedHooks) unless Redmine::Hook.listeners.any?(GkAccess::RefusedHooks)

# Everything below runs once every plugin is in (records loads after this plugin). The trace is registered whatever
# the gate says (a gate never closes a trace): the targets and the event kinds in records, so that Private made or
# ended and what a deleted account took with it are written also while the gate is closed. What is drawn is
# registered only with GK GUI Stuff (GkAccess.gui?, gate.rb).
# A records that keeps its registers open with the gate closed calls register_records! itself when it loads, so the
# targets and kinds are then registered twice with the same values, which does no harm. The call here is no
# duplicate to take away: beside a records whose own call stands behind its gate it is the only one.
# With the gate closed the method runs in a state it never ran in before, so a fault then is logged and passed over,
# as in records' own call: it must not stop the start. With the gate open a fault is raised as before.
Rails.configuration.after_initialize do
  GkAccess.records_checked!
  begin
    GkAccess.register_records!
  rescue StandardError => e
    raise if GkAccess.gui?

    Rails.logger.warn("[gk_access] register_records! failed while the gate is closed: #{e.class} #{e.message}")
  end
  next unless GkAccess.gui?

  GkAccess.register_translations!
  GkAccess::Private.register_hint!
end
# The tab Private in a project's settings, in core_stuff's register (core_stuff loads after this plugin)
Rails.configuration.after_initialize { GkAccess::Private::ProjectTab.register! if GkAccess.gui? }
# registrations.yml read through records' one reader: a label the file names that no locale has is written to the
# log at start
Rails.configuration.after_initialize { ::GkRecords::Registrations.check!(:gk_access) if GkAccess.gui? && defined?(::GkRecords::Registrations) }
