# frozen_string_literal: true

module GkAccess
  # The core patches, every one in one place with what it assumes of core in the supported series (the modules are in
  # private.rb, beside the rules they serve):
  # * User#allowed_to?(:view_private_notes): false for everyone, the administrator too, in a project with strict notes
  #   (and globally when the instance has strict notes); every private note there is marked. Core asks it in
  #   Issue#visible_journals_with_index, Journal#notified_users and select_journal_visible_user, and the conflict list
  #   in IssuesController#update. Core's own signature: the options come as a plain hash (allowed_to_globally?).
  # * Issue#visible_journals_with_index (the issue page, API, PDF, Atom): a marked note that is not the reader's own is
  #   left out, also where the place is as in Redmine now.
  # * Project.allowed_to_condition(user, :view_private_notes): core's condition, and the note is not marked. Core
  #   builds Journal.visible_notes_condition (Journal.visible, the queries' last notes, last updated by and filters,
  #   the quote) and the search's own condition on journals with it; both have journals in the query.
  # * Issue.visible_condition: core's condition, and the issue is not private, or not marked, or the user wrote it.
  #   Added after core's, so the administrator's shortcut is covered too.
  # * Issue#visible? and Journal#visible?: core's answer, and the same rule.
  # * Issue#last_updated_by without preloading: the newest note the reader reaches, not any note.
  # * Mailer.deliver_issue_edit: a marked note is sent to no one (core adds the issue's own mentions unfiltered).
  # * Validations on Journal and Issue where strict holds or the thing is marked: only the one who wrote a note or
  #   issue makes it private or not; a note with changes or attachments cannot be made private afterwards; a private
  #   issue cannot be assigned to anyone but its author.
  # * IssuesController#deny_access: the line "the issue is there and strictly private" for whoever core lets see it.
  # * User deletion (User before_destroy, before core's remove_references_before_destroy moves the rest to
  #   Anonymous): what the account holds strictly private is destroyed with it. UsersController#destroy and
  #   #bulk_destroy and MyController#destroy put the counts on the page that asks first; locking is as before.
  # The tab Private in a project's settings is no patch: it is registered in core_stuff's register project_settings_tab
  # (Private::ProjectTab, from init.rb after initialize).
  # Applied directly from init.rb, which Redmine runs inside to_prepare at start and again after every reload in
  # development mode; every prepend is guarded, so a reload never adds a module twice. A to_prepare block of its own
  # would miss the first round and be added once more on every reload.
  module Patches
    module_function

    def apply!
      ::User.prepend(Private::UserPatch) unless ::User < Private::UserPatch
      ::Project.singleton_class.prepend(Private::ProjectClassPatch) unless ::Project.singleton_class < Private::ProjectClassPatch
      ::Issue.singleton_class.prepend(Private::IssueClassPatch) unless ::Issue.singleton_class < Private::IssueClassPatch
      ::Issue.prepend(Private::IssuePatch) unless ::Issue < Private::IssuePatch
      ::Journal.prepend(Private::JournalPatch) unless ::Journal < Private::JournalPatch
      ::Mailer.singleton_class.prepend(Private::MailerClassPatch) unless ::Mailer.singleton_class < Private::MailerClassPatch
      ::IssuesController.prepend(Private::IssuesControllerPatch) unless ::IssuesController < Private::IssuesControllerPatch
      ::UsersController.prepend(Private::UsersControllerPatch) unless ::UsersController < Private::UsersControllerPatch
      ::MyController.prepend(Private::MyControllerPatch) unless ::MyController < Private::MyControllerPatch
    end
  end
end
