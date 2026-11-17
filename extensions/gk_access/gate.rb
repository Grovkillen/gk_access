# frozen_string_literal: true

module GkAccess
  # The gate to GK GUI Stuff, which access requires (IDENTITY.yml, gk_gui_stuff). It is open when GK GUI Stuff answers
  # the gate's questions, its base version (the version without a candidate's suffix) is the lowest one access needs or
  # later, and its own gate is open; candidates of one base version are not told apart.
  #
  # A gate closes only the interface, never a protection or a trace. Closed, the gate closes what a person works with:
  # the pages, the menu item, the REST API, the explanation by Private (the lock and the line, their stylesheet and
  # script) and what access registers in other plugins to be drawn (records' appearance setting and the check of
  # registrations.yml, fields' translations, the tab Private in core_stuff's register). It never closes:
  # * the nine core patches (patches.rb, the modules in private.rb): what is strictly private reaches only the one who
  #   wrote it, its rules are validated, and an account that is deleted takes what it holds strictly private with it;
  # * the marking: a private issue or note made where strict holds is marked strict, also while the gate is closed;
  # * the trace: the targets and the event kinds in records (GkAccess.register_records!, from init.rb after
  #   initialize whatever the gate says), so that strict Private made or ended on an issue and what a deleted account
  #   took with it are written as events while the gate is closed; records writes them and says in their details that
  #   the gate was closed;
  # * the questions other plugins ask about levels (GkAccess.levels, level, sees?, ceiling, levels_seen, register_user
  #   and the rest of core.rb): they answer as with an open gate, since what a person sees follows from them;
  # * the answer after a refused change of a note's Private (RefusedHooks), which draws the note as it stands, so that
  #   nobody takes a note for private that is not;
  # * the permissions (Manage Private and the two OAuth scopes): init.rb registers them whatever the gate says. Core's
  #   role form lists only the permissions that are registered and Role#permissions= writes the whole list, so a role
  #   saved while they were away would lose them. With the gate closed they open nothing: the controllers answer 404.
  # The settings page says the first thing that is not met in one line of core's own form (<p class="warning">) before
  # the About box, and that protection and traces hold all the same; the migrations run all the same.
  #
  # Access loads before gk_gui_stuff (Redmine loads the plugins in the order of their directories' names), so init.rb
  # cannot ask the gate: the registrations behind the gate come after initialize, and the menu, the controllers and
  # the listener ask at each request.

  # The lowest base version the gate opens for; IDENTITY.yml requires the same base and a test holds the two together
  GUI_STUFF_MIN = '1.05.000'

  #   GkAccess.gui_closed -> nil when the gate is open; otherwise the first thing that is not met: :missing (no GK GUI
  #   Stuff), :old (it does not answer open?, or its base version is older than GUI_STUFF_MIN) or :inactive (its own
  #   gate is closed)
  def self.gui_closed
    return :missing unless defined?(::GkGuiStuff)
    return :old unless ::GkGuiStuff.respond_to?(:open?) && ::GkGuiStuff.respond_to?(:version_at_least?) &&
                       ::GkGuiStuff.version_at_least?(GUI_STUFF_MIN)
    return :inactive unless ::GkGuiStuff.open?

    nil
  rescue StandardError
    :missing
  end

  #   GkAccess.gui? -> true when gui_closed has nothing to say
  def self.gui? = gui_closed.nil?

  module Gate
    # The hook methods a view or controller listener answers (view_*, controller_*, model_*). Redmine asks a listener
    # respond_to?(hook) once and keeps the answer (Redmine::Hook.hook_listeners), so a closed gate keeps every hook of
    # the explanation's listener silent. A listener is registered as soon as its class is defined
    # (Listener.inherited), so the gate is in the listener and not in init.rb.
    HOOK = /\A(view|controller|model)_/

    module Listener
      def respond_to?(name, include_all = false)
        return false if HOOK.match?(name.to_s) && !GkAccess.gui?

        super
      end
    end

    # Every access controller (the pages and the REST API) is closed without GK GUI Stuff: core's 404. A plain
    # before_action, after the ones ApplicationController has (the session, the user, the language), so that the 404 is
    # drawn for the person and in the language of the request; before the controller's own (require_admin and the like)
    module Controller
      def self.included(base)
        base.before_action :gk_access_gate
      end

      private

      def gk_access_gate
        render_404 unless GkAccess.gui?
      end
    end
  end
end
