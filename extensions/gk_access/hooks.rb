# frozen_string_literal: true

module GkAccess
  # With the appearance setting Private::HINT on, the person sees which kind of Private holds and who sees what is private: by the check box Private in the
  # issue form, by the check box for private notes, on a private issue and by a private note in the history.
  # The explanation is closed without GK GUI Stuff (Gate::Listener): no hook of this listener answers then.
  class Hooks < Redmine::Hook::ViewListener
    include GkAccess::Gate::Listener

    render_on :view_issues_form_details_bottom, partial: 'gk_access_hooks/form_hint'
    render_on :view_issues_edit_notes_bottom, partial: 'gk_access_hooks/notes_hint'
    render_on :view_issues_show_details_bottom, partial: 'gk_access_hooks/issue_hint'
    render_on :view_issues_history_journal_bottom, partial: 'gk_access_hooks/journal_hint'

    # Icon only: an issue's lock after the badges of its head, through the hook before div.issue (view_issues_show_top,
    # GK Core Stuff's layout_hooks). Where another plugin's copy of the issue view leaves the hook out, the lock comes with
    # view_issues_show_details_bottom and stays there; nothing is looked for or moved.
    def view_issues_show_top(context = {})
      issue = context[:issue]
      c = context[:controller]
      return '' unless issue && c && context[:hook_caller].respond_to?(:render) && GkAccess::Private.ready? && GkAccess::Private.hint_shape == 'icon'

      html = context[:hook_caller].render(partial: 'gk_access_hooks/issue_hint', locals: { issue: issue, head: true })
      c.instance_variable_set(:@gk_access_issue_lock_drawn, true)
      html
    end

    # The lock's place on its row, only where the explanation is drawn; with the row off the page has nothing of this
    def view_layouts_base_html_head(_context = {})
      return '' unless GkAccess::Private.ready? && GkAccess::Private.hint_on?

      stylesheet_link_tag('gk_access', plugin: 'gk_access') + javascript_include_tag('gk_access', plugin: 'gk_access')
    end
  end

  # A note whose change of Private was refused: Redmine's answer draws it as it was sent, so the note's real state and
  # the refusal are drawn after it. It belongs to the protection and is not behind the gate (a gate never closes a
  # protection): without it a note whose change was refused would stand on the page as private when it is not, or the
  # other way round, until the page is read again. Plain DOM and core's own helpers, nothing of GK GUI Stuff.
  class RefusedHooks < Redmine::Hook::ViewListener
    render_on :view_journals_update_js_bottom, partial: 'gk_access_hooks/journal_refused'
  end
end
