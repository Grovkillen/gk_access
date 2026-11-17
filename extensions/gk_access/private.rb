# frozen_string_literal: true

module GkAccess
  # Private: core's private issues and private notes work as in Redmine unless strict is chosen, and what is strictly
  # private never becomes ordinary private again. The choice is made for private issues and private notes each, for
  # the instance on Administration > Levels, and a project can be made stricter in its settings (never less strict
  # than the instance). The choice decides what happens to what becomes private from then on: a private issue
  # or note made where strict holds is marked strict (gk_access_strict_items), and making a place strict marks what
  # is private there already. A mark stays: the place going back to as in Redmine, or the issue moving, never makes
  # it ordinary private again; only its author ends it, by making it not private. A strictly private note or issue
  # reaches only the one who wrote it: View private notes, the roles' issue visibility, assignment, groups, watchers
  # and the administrator give no access. Whoever would have seen it under core's rules is told that it is there and
  # strictly private (never who, what or when); the administrator sees the counts per project. An account that is
  # deleted takes what it holds strictly private with it, so that it never reaches anyone else (the page asking
  # before says how many). With the appearance setting HINT on the person sees which kind holds and who sees the thing.
  # When the plugin's tables cannot be read (missing, or a failing read) Private answers as strict everywhere and
  # writes the failure to the log; it is never taken for "as in Redmine".
  #
  # The core patches' modules are at the end of this module; patches.rb applies them and says what each assumes of core.
  module Private
    module_function

    KINDS = %i[issues notes].freeze

    # Whether Private's tables can be read, quietly: for what is only drawn, counted or marked (the explanation, the
    # tab, the counts, the marking). The questions that decide what a person sees do not build on it (tables!).
    def ready?
      GkAccess.ready? && ::GkAccessStrictItem.table_exists?
    rescue StandardError
      false
    end

    # The questions that decide what a person sees (strict?, marked?, any_marked?, marked_ids, marked_sql) never take
    # tables they cannot read for "as in Redmine". A missing table (the migrations have not run, or were run down) or a
    # failing read gives the strict answer: a private issue or note reaches only its author while it lasts. The failure
    # is written to the log each time such an answer is given. Raises Unreadable when a table is missing; a failing
    # check raises as it is.
    def tables!
      return if ::GkAccessLevel.table_exists? && ::GkAccessRoleLevel.table_exists? && ::GkAccessPrivateMode.table_exists? &&
                ::GkAccessStrictItem.table_exists?

      raise GkAccess::Unreadable, 'the tables of Private are missing'
    end

    # The strict answer to a question that could not be read, with the failure in the log. Each question writes its own
    # line, as the questions about levels do.
    def taken_strict(error, answer = true)
      Rails.logger&.warn("[gk_access] Private not read, taken as strict: #{error.class} #{error.message}")
      answer
    end

    # What is written or changed (a mark, an event) builds only on what was read, never on the strict answer given when
    # nothing could be read: the block's answer, or nil with "Private not read, <what>" in the log when it fails
    def when_read(what)
      yield
    rescue StandardError => e
      Rails.logger&.warn("[gk_access] Private not read, #{what}: #{e.class} #{e.message}")
      nil
    end

    # Whether the thing is private now (a mark is only ever on what is private)
    def private_item?(item) = item.is_a?(::Journal) ? item.private_notes? == true : item.is_private? == true

    # The explanation beside Private (which kind holds and who sees it, by the check boxes, on a private issue and by a
    # private note): an appearance setting of its own in records' register, off in a new installation. Off, the hooks
    # draw nothing and Redmine's page is untouched; Private itself works the same. shape is the form it takes: full, the
    # lock and the text under the note and on the issue; icon, the lock alone, a press on it opens the text, first on the
    # note's fold list (GK GUI Stuff's slot) or after the badge Private in the head. By the check boxes it is the lock in both.
    HINT = 'access.private_hint'
    HINT_SHAPES = %w[full icon].freeze
    HINT_FOOTPRINT = { applies: %w[server script], footprint: { anchors: ['.gk-access-private-hint'], pages: %w[core.issue] } }.freeze

    # A change of a note's Private that was refused here: the note as it stands in the database, nil when it is not
    # such a note (nothing refused, or a note core has taken away)
    def refused_note(journal)
      return nil unless journal && !journal.frozen? && journal.errors.include?(:private_notes)

      ::Journal.find_by(id: journal.id)
    end

    def hint_on?(user = ::User.current)
      return false unless ::GkAccess.gui? # the explanation is closed without GK GUI Stuff (gate.rb); Private itself is not

      defined?(::GkRecords::AppearanceSettings) ? ::GkRecords::AppearanceSettings.on_for?(HINT, user) : false
    end

    # The form the person gets, one of HINT_SHAPES; nil while the setting is off for the person
    def hint_shape(user = ::User.current)
      return nil unless hint_on?(user)

      shape = ::GkRecords::AppearanceSettings.person_value(HINT, 'shape', user).to_s
      HINT_SHAPES.include?(shape) ? shape : HINT_SHAPES.first
    end

    # In records' register (records loads after this plugin); the footprint only with a register that takes it
    def register_hint!
      return unless defined?(::GkRecords::AppearanceSettings)

      r = ::GkRecords::AppearanceSettings
      takes = r.method(:register).parameters.map(&:last)
      r.register(HINT, plugin: :gk_access, group: :issue, person: :segment,
                       label: :label_gk_access_appearance_private_hint, help: :text_gk_access_appearance_private_hint,
                       values: { 'shape' => { kind: :choice, default: HINT_SHAPES.first, person: true, label: :label_gk_access_appearance_private_hint_shape,
                                              choices: -> { HINT_SHAPES.map { |s| [::I18n.t(:"label_gk_access_appearance_private_hint_shape_#{s}"), s] } } } },
                       preview: 'gk_access_appearance/previews/private_hint',
                       **(takes.include?(:footprint) && takes.include?(:applies) ? HINT_FOOTPRINT : {}))
    end

    def column(kind) = kind.to_sym == :notes ? :notes_strict : :issues_strict

    # ------------------------------------------------------------------ the choice (what becomes strict from now on)

    # Asked of the table every time, never remembered: a scenario's wipe empties the table, and a remembered answer
    # would then say strict holds when it does not. Strict when the tables cannot be read (tables!).
    def instance_strict?(kind)
      tables!
      ::GkAccessPrivateMode.where(project_id: nil, column(kind) => true).exists?
    rescue StandardError => e
      taken_strict(e)
    end

    # The project's own choice, without the instance's; strict when the tables cannot be read
    def project_strict?(kind, project)
      return false unless project

      tables!
      ::GkAccessPrivateMode.where(project_id: project.id, column(kind) => true).exists?
    rescue StandardError => e
      taken_strict(e)
    end

    # Does strict hold for what becomes private of this kind in this project (or, without a project, the instance)?
    def strict?(kind, project = nil)
      instance_strict?(kind) || project_strict?(kind, project)
    end

    # The same as read, never a guess: raises when the tables cannot be read (for marking, events and REST)
    def strict_read?(kind, project = nil)
      tables!
      ::GkAccessPrivateMode.where(project_id: nil, column(kind) => true).exists? ||
        (!project.nil? && ::GkAccessPrivateMode.where(project_id: project.id, column(kind) => true).exists?)
    end

    # ------------------------------------------------------------------ the marks (what is strict, for good)

    def kind_of(item) = item.is_a?(::Journal) ? :notes : :issues

    # When the marks cannot be read, whatever is private counts as marked
    def marked?(item)
      return false unless item&.id

      tables!
      ::GkAccessStrictItem.where(item_type: ::GkAccessStrictItem.type_of(kind_of(item)), item_id: item.id).exists?
    rescue StandardError => e
      taken_strict(e, private_item?(item))
    end

    # Whether the thing is marked, as read, never a guess: raises when the marks cannot be read
    def marked_read?(item)
      return false unless item&.id

      tables!
      ::GkAccessStrictItem.where(item_type: ::GkAccessStrictItem.type_of(kind_of(item)), item_id: item.id).exists?
    end

    def mark!(item)
      return if marked_read?(item)

      ::GkAccessStrictItem.create!(item_type: ::GkAccessStrictItem.type_of(kind_of(item)), item_id: item.id, created_at: ::Time.current)
    end

    # Only when the author ends Private (validated), or the thing is gone
    def unmark!(item)
      ::GkAccessStrictItem.where(item_type: ::GkAccessStrictItem.type_of(kind_of(item)), item_id: item.id).delete_all if ready? && item&.id
    end

    # Yes when the marks cannot be read: the lists then take every private one as marked (marked_sql)
    def any_marked?(kind)
      tables!
      ::GkAccessStrictItem.where(item_type: ::GkAccessStrictItem.type_of(kind)).exists?
    rescue StandardError => e
      taken_strict(e)
    end

    # SQL for what a person sees: the id in id_column is marked strict for the kind. When the marks cannot be read
    # (the tables are missing, or reading them fails), every one counts as marked, without naming the table (it would
    # fail the whole query), with the failure in the log.
    def marked_sql(kind, id_column)
      tables!
      ::GkAccessStrictItem.where(item_type: ::GkAccessStrictItem.type_of(kind)).exists?
      marked_subquery(kind, id_column)
    rescue StandardError => e
      taken_strict(e, '1=1')
    end

    # SQL naming the marks as they are, for what counts, marks or deletes (never a guess: the query fails when the marks
    # cannot be read)
    def marked_subquery(kind, id_column)
      t = ::GkAccessStrictItem.table_name
      type = ::GkAccessStrictItem.connection.quote(::GkAccessStrictItem.type_of(kind))
      "#{id_column} IN (SELECT #{t}.item_id FROM #{t} WHERE #{t}.item_type = #{type})"
    end

    # Of the ids, those marked; all of them when the marks cannot be read
    def marked_ids(kind, ids)
      return [] if ids.blank?

      tables!
      ::GkAccessStrictItem.where(item_type: ::GkAccessStrictItem.type_of(kind), item_id: ids).pluck(:item_id)
    rescue StandardError => e
      taken_strict(e, Array(ids))
    end

    # The private things in a place (project nil: the whole instance) that are not marked yet
    def unmarked(kind, project = nil)
      rel = if kind.to_sym == :notes
              ::Journal.where(private_notes: true).joins(:issue)
            else
              ::Issue.where(is_private: true)
            end
      rel = rel.where(::Issue.table_name => { project_id: project.id }) if project
      id = kind.to_sym == :notes ? "#{::Journal.table_name}.id" : "#{::Issue.table_name}.id"
      rel.where.not(marked_subquery(kind, id))
    end

    def mark_place!(kind, project = nil)
      now = ::Time.current
      type = ::GkAccessStrictItem.type_of(kind)
      unmarked(kind, project).pluck(:id).each_slice(500) do |ids|
        ::GkAccessStrictItem.insert_all(ids.map { |i| { item_type: type, item_id: i, token: ::GkAccessStrictItem.new_token, created_at: now } })
      end
    end

    # The thing's anonymous identity (SP-XXXX-XXXX), nil when it is not strictly private
    def token_for(item)
      return nil unless ready? && item&.id

      ::GkAccessStrictItem.where(item_type: ::GkAccessStrictItem.type_of(kind_of(item)), item_id: item.id).pick(:token)
    rescue StandardError
      nil
    end

    # The anonymous identities of what an account holds strictly private: { issues: [...], notes: [...] }
    def held_tokens(user)
      return { issues: [], notes: [] } unless ready? && user&.id

      t = ::GkAccessStrictItem.table_name
      { issues: ::GkAccessStrictItem.where(item_type: 'Issue', item_id: ::Issue.where(author_id: user.id, is_private: true).select(:id)).order(:token).pluck(:token),
        notes: ::GkAccessStrictItem.where(item_type: 'Journal', item_id: ::Journal.where(user_id: user.id, private_notes: true).select(:id))
                                   .order("#{t}.token").pluck(:token) }
    end

    # Strictly private things per project, for the administrator: { project => { issues: n, notes: n } }
    def counts_per_project
      return {} unless ready?

      out = Hash.new { |h, k| h[k] = { issues: 0, notes: 0 } }
      ::Issue.where(is_private: true).where(marked_subquery(:issues, "#{::Issue.table_name}.id")).group(:project_id).count.each do |pid, n|
        out[pid][:issues] = n
      end
      ::Journal.where(private_notes: true).joins(:issue).where(marked_subquery(:notes, "#{::Journal.table_name}.id"))
               .group("#{::Issue.table_name}.project_id").count.each { |pid, n| out[pid][:notes] = n }
      projects = ::Project.where(id: out.keys).index_by(&:id)
      out.to_h.filter_map { |pid, c| [projects[pid], c] if projects[pid] }.sort_by { |p, _| p.name }
    end

    # What an account has written that is strictly private (it then cannot be deleted)
    def held_by(user)
      return { issues: 0, notes: 0 } unless ready? && user&.id

      { issues: ::Issue.where(author_id: user.id, is_private: true).where(marked_subquery(:issues, "#{::Issue.table_name}.id")).count,
        notes: ::Journal.where(user_id: user.id, private_notes: true).where(marked_subquery(:notes, "#{::Journal.table_name}.id")).count }
    end

    def holds_strict?(user) = held_by(user).values.sum.positive?

    # The projects where the account holds something strictly private and GK Retention has a preservation hold: the
    # account is then not deleted (it can be locked) while the hold lasts, since what is held may not be destroyed
    def held_back(user)
      return [] unless ready? && user&.id && defined?(::GkRetention::Preservation) && ::GkRetention::Preservation.respond_to?(:hold_for)

      ids = ::Issue.where(author_id: user.id, is_private: true).where(marked_subquery(:issues, "#{::Issue.table_name}.id")).distinct.pluck(:project_id)
      ids |= ::Journal.where(user_id: user.id, private_notes: true).where(marked_subquery(:notes, "#{::Journal.table_name}.id"))
                      .joins(:issue).distinct.pluck("#{::Issue.table_name}.project_id")
      ::Project.where(id: ids).sorted.select { |p| (hold = ::GkRetention::Preservation.hold_for(p)) && hold.held? }
    rescue StandardError
      []
    end

    # GK Retention lets only an administrator delete physically: with it, deleting one's own account that holds
    # something strictly private is refused (an administrator deletes it)
    def admin_needed?(user, by = ::User.current)
      defined?(::GkRetention) && ::GkRetention.respond_to?(:allowing_destroy) && !by&.admin? && holds_strict?(user)
    end

    def held_back_message(user, projects = held_back(user))
      ::I18n.t(:error_gk_access_user_strict_held, name: user.name, projects: join_words(projects.map(&:name)))
    end

    # Said on the page that asks before the deletion: how many, and their anonymous identities only, never what
    # the issues or notes are
    def deletion_warning(user)
      h = held_by(user)
      tokens = held_tokens(user).values.flatten
      ::I18n.t(:text_gk_access_user_strict_removed, name: user.name, issues: h[:issues], notes: h[:notes], tokens: tokens.join(', '))
    end

    # An account being deleted takes what it holds strictly private with it, so that it stays strictly private: core
    # would otherwise make Anonymous its author, and it would then reach no one or, made public, everyone. Removed before core moves the rest to
    # Anonymous; an event in records says how many, never what.
    def remove_held_by!(user)
      return unless ready? && user&.id

      h = held_by(user)
      return if h.values.sum.zero?

      tokens = held_tokens(user)
      # GK Retention closes core's destroy for what it handles; this deletion is the organisation's own choice when it
      # deletes the account, so it goes through retention's way (a preservation hold refuses it before, held_back)
      through = ->(&blk) { defined?(::GkRetention) && ::GkRetention.respond_to?(:allowing_destroy) ? ::GkRetention.allowing_destroy(&blk) : blk.call }
      through.call do
        ::Journal.where(user_id: user.id, private_notes: true).where(marked_subquery(:notes, "#{::Journal.table_name}.id")).find_each(&:destroy!)
        ::Issue.where(author_id: user.id, is_private: true).where(marked_subquery(:issues, "#{::Issue.table_name}.id")).find_each do |i|
          i.reload.destroy! if ::Issue.exists?(i.id) # a subtask may already be gone with its parent
        end
      end
      return unless GkAccess.records?

      row = ::GkAccessPrivateMode.find_or_create_by!(project_id: nil) { |r| r.updated_at = ::Time.current }
      # how many and their anonymous identities, never the account, the project, the subject or the text
      GkAccess.write_event(row, 'access.strict_removed', details: { 'issues' => h[:issues], 'notes' => h[:notes],
                                                                     'items' => tokens[:issues] + tokens[:notes] }, user: ::User.current)
    end

    # ------------------------------------------------------------------ who

    # Kept for the callers that cleared a remembered answer; nothing is remembered now
    def reset!; end

    def mine?(user, author_id)
      user ||= ::User.current
      user.logged? && author_id.present? && user.id == author_id && !looked_at?
    end

    # See as (gk_people): an administrator looks at the pages as the person, with the person's account as the current
    # user. Private goes first: what is strictly private stays the person's own, so while someone else looks nothing of
    # hers that is strictly private is shown, as if she had not written it. Her own login is not affected.
    def looked_at?
      defined?(::GkPeople::SeeAs) && ::GkPeople::SeeAs.respond_to?(:active?) && ::GkPeople::SeeAs.active?
    rescue StandardError
      false
    end

    # core's own answer, without the strict rule (for the line "it is there and strictly private")
    def core_visible?(issue, user)
      was = ::Thread.current[:gk_access_core_only]
      ::Thread.current[:gk_access_core_only] = true
      issue.visible?(user)
    ensure
      ::Thread.current[:gk_access_core_only] = was
    end

    def core_only? = ::Thread.current[:gk_access_core_only] == true

    # The person is kept from this issue only by strict: core would have let her see it
    def hidden_by_strict?(issue, user = ::User.current)
      issue&.is_private? && marked?(issue) && !mine?(user, issue.author_id) && core_visible?(issue, user)
    end

    # The roles that hold in a project: those of its members, and Non member when it is public
    def project_roles(project)
      ids = ::MemberRole.joins(:member).where(members: { project_id: project.id }).distinct.pluck(:role_id)
      roles = ::Role.where(id: ids).sorted.to_a
      roles << ::Role.non_member if project.is_public?
      roles.uniq
    end

    # The roles that see every private issue (core: issue visibility All issues) or every private note (View private
    # notes) in the project, under core's rules
    def core_roles(kind, project)
      return [] unless project

      project_roles(project).select do |r|
        next false unless r.has_permission?(:view_issues)

        kind.to_sym == :notes ? r.has_permission?(:view_private_notes) : r.issues_visibility == 'all'
      end
    end

    # "a, b och c" in the person's language (core's locales do not all give Rails' connectors)
    def join_words(list)
      list = Array(list)
      return list.first.to_s if list.size < 2

      "#{list[0..-2].join(', ')} #{::I18n.t(:text_gk_access_and)} #{list.last}"
    end

    # Which kind holds and who sees a private issue or note, said to the person: on the issue form and the notes'
    # check box (item: the thing as it is, or nil for what is being written), on a private issue and by a private
    # note. A marked thing is strict wherever it is; otherwise the place's choice decides. Returns
    # { strict:, label:, text: }.
    def explain(kind, project, item: nil, author: nil, assignee: nil)
      kind = kind.to_sym
      strict = marked?(item) || ((item.nil? || item.new_record? || !private_now?(item)) && strict?(kind, project))
      own = author && author.id == ::User.current.id
      writer = own ? ::I18n.t(:text_gk_access_who_you) : author&.name.to_s
      writer = ::I18n.t(:text_gk_access_who_writer) if writer.blank?
      label = ::I18n.t(strict ? :label_gk_access_private_strict : :label_gk_access_private_core)
      if strict
        return { strict: true, label: label, text: ::I18n.t(:"text_gk_access_explain_#{kind}_strict", writer: writer) }
      end

      who = [::I18n.t(:text_gk_access_who_wrote, name: writer)]
      if kind == :issues
        who << (assignee ? ::I18n.t(:text_gk_access_who_assigned, name: assignee.name) : ::I18n.t(:text_gk_access_who_assignee))
      end
      roles = core_roles(kind, project).map(&:name)
      who << ::I18n.t(:"text_gk_access_who_roles_#{kind}", roles: join_words(roles)) if roles.any?
      who << ::I18n.t(:text_gk_access_who_admins)
      { strict: false, label: label, text: ::I18n.t(:"text_gk_access_explain_#{kind}_core", who: join_words(who)) }
    end

    def private_now?(item) = item.is_a?(::Journal) ? item.private_notes_in_database : item.is_private_in_database

    # What becomes strictly private and who loses access, in the instance (project nil) or one project, if strict is
    # chosen there for the kinds
    def inventory(project = nil, kinds = KINDS)
      kinds = Array(kinds).map(&:to_sym)
      notes = kinds.include?(:notes) ? unmarked(:notes, project) : ::Journal.none
      issues = kinds.include?(:issues) ? unmarked(:issues, project) : ::Issue.none
      losing = []
      roles = project ? project_roles(project) : ::Role.sorted.to_a
      roles.each do |r|
        losing << { 'kind' => 'view_private_notes', 'name' => r.name } if kinds.include?(:notes) && r.has_permission?(:view_private_notes)
        losing << { 'kind' => 'issues_all', 'name' => r.name } if kinds.include?(:issues) && r.issues_visibility == 'all' && r.has_permission?(:view_issues)
      end
      if kinds.include?(:issues)
        assigned = issues.where.not(assigned_to_id: nil).where("#{::Issue.table_name}.assigned_to_id <> #{::Issue.table_name}.author_id")
        ::Principal.where(id: assigned.select(:assigned_to_id)).sort_by(&:name).each do |p|
          losing << { 'kind' => 'assigned', 'name' => p.name, 'count' => assigned.where(assigned_to_id: p.id).count }
        end
        watched = ::Watcher.where(watchable_type: 'Issue', watchable_id: issues.select(:id)).where.not(user_id: issues.select(:author_id))
        losing << { 'kind' => 'watchers', 'count' => watched.select(:user_id).distinct.count } if watched.exists?
      end
      admins = ::User.active.where(admin: true).count
      losing << { 'kind' => 'admins', 'count' => admins } if admins.positive?
      { 'private_notes' => notes.count, 'private_issues' => issues.count, 'losing' => losing }
    end

    # The choice for the instance (project nil) or a project, with an event in records. Made stricter, what is private
    # there already is marked strict. Made less strict, what is marked stays strict; only what becomes private from
    # then on is as in Redmine. Only an administrator makes a project less strict (may_loosen: REST asks it of the token).
    # Nothing changed is no event, also when the row is made here for the first time.
    def set_mode!(project, issues:, notes:, user: ::User.current, may_loosen: user&.admin?)
      GkAccess.require_records!
      cast = ->(v) { ActiveModel::Type::Boolean.new.cast(v) == true }
      wanted = { issues: cast.(issues), notes: cast.(notes) }
      row = ::GkAccessPrivateMode.find_or_initialize_by(project_id: project&.id)
      before = { issues: row.issues_strict?, notes: row.notes_strict? }
      return row if before == wanted && row.persisted?

      if project && !may_loosen && KINDS.any? { |k| before[k] && !wanted[k] }
        raise GkAccess::Error, ::I18n.t(:error_gk_access_loosen_admin_only)
      end

      tighter = KINDS.select { |k| wanted[k] && !before[k] }
      inv = tighter.any? ? inventory(project, tighter) : nil
      ::GkAccessPrivateMode.transaction do
        row.issues_strict = wanted[:issues]
        row.notes_strict = wanted[:notes]
        row.updated_at = ::Time.current
        row.save!
        tighter.each { |k| mark_place!(k, project) }
        details = { 'scope' => project ? project.identifier : 'instance' }
        KINDS.each { |k| details[k.to_s] = [mode_word(before[k]), mode_word(wanted[k])] if before[k] != wanted[k] }
        details.merge!('marked_notes' => inv['private_notes'], 'marked_issues' => inv['private_issues']) if inv
        GkAccess.write_event(row, 'access.private_mode', details: details, user: user) if before != wanted
      end
      row
    end

    def mode_word(strict) = strict ? 'strict' : 'core'

    # The kinds a REST call asks for ('strict' or 'core' per kind), as { issues: bool, notes: bool }; a kind not given
    # keeps the row's. nil when a value is neither word.
    def wanted_kinds(given, row)
      given = given.respond_to?(:to_unsafe_h) ? given.to_unsafe_h : (given.is_a?(Hash) ? given : {})
      KINDS.each_with_object({}) do |k, h|
        v = given[k.to_s] || given[k]
        if v.nil?
          h[k] = row ? row.strict?(k) : false
        elsif %w[strict core].include?(v.to_s)
          h[k] = v.to_s == 'strict'
        else
          return nil
        end
      end
    end

    # ------------------------------------------------------------------ core patches

    module UserPatch
      def self.prepended(base)
        base.before_destroy :gk_access_remove_strict, prepend: true
      end

      # core's own signature (options as a plain hash; allowed_to_globally? passes one)
      def allowed_to?(action, context, options = {}, &block)
        if action == :view_private_notes && (context.is_a?(::Project) || context.nil?) && !::GkAccess::Private.core_only?
          return false if ::GkAccess::Private.strict?(:notes, context)
        end

        super
      end

      private

      def gk_access_remove_strict
        held = ::GkAccess::Private.held_back(self)
        if held.any?
          errors.add(:base, ::GkAccess::Private.held_back_message(self, held))
          throw :abort
        end
        if ::GkAccess::Private.admin_needed?(self)
          errors.add(:base, ::I18n.t(:error_gk_access_user_strict_admin_only))
          throw :abort
        end
        ::GkAccess::Private.remove_held_by!(self)
      end
    end

    module ProjectClassPatch
      def allowed_to_condition(user, permission, options = {}, &block)
        return super unless permission == :view_private_notes && ::GkAccess::Private.any_marked?(:notes)

        # a marked note through the roles never; its author always (core's search asks only this condition for
        # private notes, without the author's own exception that Journal.visible_notes_condition has)
        marked = ::GkAccess::Private.marked_sql(:notes, "#{::Journal.table_name}.id")
        own = user&.logged? && !::GkAccess::Private.looked_at? ? "#{::Journal.table_name}.user_id = #{user.id.to_i}" : '1=0'
        "(((#{super}) AND NOT (#{marked})) OR ((#{marked}) AND #{own}))"
      end
    end

    module IssueClassPatch
      def visible_condition(user, options = {})
        base = super
        return base unless ::GkAccess::Private.any_marked?(:issues)

        mine = user&.logged? && !::GkAccess::Private.looked_at? ? " OR #{table_name}.author_id = #{user.id.to_i}" : ''
        marked = ::GkAccess::Private.marked_sql(:issues, "#{table_name}.id")
        "(#{base}) AND (#{table_name}.is_private = #{connection.quoted_false} OR NOT (#{marked})#{mine})"
      end
    end

    module IssuePatch
      def self.prepended(base)
        base.validate :gk_access_private_rules
        base.after_save :gk_access_private_mark
        base.after_update :gk_access_private_event
        base.after_destroy { ::GkAccess::Private.unmark!(self) }
      end

      def visible?(usr = nil)
        return false unless super
        return true if ::GkAccess::Private.core_only? || !is_private?

        !::GkAccess::Private.marked?(self) || ::GkAccess::Private.mine?(usr || ::User.current, author_id)
      end

      def visible_journals_with_index(user = ::User.current)
        result = super
        privates = result.select(&:private_notes?)
        return result if privates.empty?

        marked = ::GkAccess::Private.marked_ids(:notes, privates.map(&:id))
        return result if marked.empty?

        result.reject { |j| marked.include?(j.id) && !::GkAccess::Private.mine?(user, j.user_id) }
      end

      def last_updated_by
        return super if @last_updated_by || !::GkAccess::Private.any_marked?(:notes)

        u = ::User.current
        own = u.logged? && !::GkAccess::Private.looked_at? ? " OR #{::Journal.table_name}.user_id = #{u.id.to_i}" : ''
        marked = ::GkAccess::Private.marked_sql(:notes, "#{::Journal.table_name}.id")
        journals.where("#{::Journal.table_name}.private_notes = #{self.class.connection.quoted_false} OR NOT (#{marked})#{own}")
                .reorder(id: :desc).first.try(:user)
      end

      private

      # Marked, or becoming private where strict holds
      def gk_access_strict_here?
        ::GkAccess::Private.marked?(self) || (is_private? && ::GkAccess::Private.strict?(:issues, project))
      end

      def gk_access_private_rules
        return unless gk_access_strict_here?

        if persisted? && will_save_change_to_is_private? && !::GkAccess::Private.mine?(::User.current, author_id_in_database)
          errors.add(:is_private, :gk_access_owner_only)
        end
        return unless is_private? && assigned_to_id.present? && assigned_to_id != author_id

        errors.add(:assigned_to_id, :gk_access_private_assigned)
      end

      # Private where strict holds: marked, for good. Made not private by its author: the mark ends.
      def gk_access_private_mark
        return unless ::GkAccess::Private.ready?

        if is_private?
          # only on what was read: a guess while the tables cannot be read never makes a mark that stays
          ::GkAccess::Private.when_read('not marked') { ::GkAccess::Private.mark!(self) if ::GkAccess::Private.strict_read?(:issues, project) }
        elsif saved_change_to_is_private?
          ::GkAccess::Private.unmark!(self)
        end
      end

      # Strict Private made or ended is an event in records (core's journal has the change of the attribute as well).
      # Only strict: an ordinary private issue made public is core's journal alone. after_update runs before
      # after_save, so when the author ends strict Private the mark is still there here. Only on what was read: while
      # Private's tables cannot be read the strict answer is a guess, and an event would say strict Private was made or ended.
      def gk_access_private_event
        return unless saved_change_to_is_private? && ::GkAccess.records? && ::GkAccess::Private.ready?
        return unless ::GkAccess::Private.when_read('no event') { ::GkAccess::Private.marked_read?(self) || ::GkAccess::Private.strict_read?(:issues, project) }

        ::GkAccess.write_event(self, 'access.private', details: { 'is_private' => saved_change_to_is_private }, user: ::User.current)
      end
    end

    module JournalPatch
      def self.prepended(base)
        base.validate :gk_access_private_rules, on: :update
        base.after_save :gk_access_private_mark
        base.after_destroy { ::GkAccess::Private.unmark!(self) }
      end

      def visible?(*args)
        return false unless super(*args)
        return true if !private_notes? || ::GkAccess::Private.core_only?

        !::GkAccess::Private.marked?(self) || ::GkAccess::Private.mine?(args.first || ::User.current, user_id)
      end

      private

      def gk_access_private_rules
        return unless will_save_change_to_private_notes?
        return unless ::GkAccess::Private.marked?(self) || (private_notes? && ::GkAccess::Private.strict?(:notes, project))

        errors.add(:private_notes, :gk_access_owner_only) unless ::GkAccess::Private.mine?(::User.current, user_id)
        return unless private_notes? && (details.any? || attachments.any?)

        errors.add(:private_notes, :gk_access_private_with_details)
      end

      def gk_access_private_mark
        return unless ::GkAccess::Private.ready?

        if private_notes?
          # only on what was read: a guess while the tables cannot be read never makes a mark that stays
          ::GkAccess::Private.when_read('not marked') { ::GkAccess::Private.mark!(self) if ::GkAccess::Private.strict_read?(:notes, project) }
        elsif saved_change_to_private_notes?
          ::GkAccess::Private.unmark!(self)
        end
      end
    end

    module MailerClassPatch
      def deliver_issue_edit(journal)
        return if journal.private_notes? && ::GkAccess::Private.marked?(journal)

        super
      end
    end

    # "The issue exists but is strictly private", for whoever core lets see it; anyone else gets core's own answer
    module IssuesControllerPatch
      def deny_access
        if @issue.is_a?(::Issue) && User.current.logged? && ::GkAccess::Private.hidden_by_strict?(@issue)
          return render_403(message: :notice_gk_access_strict_exists)
        end

        super
      end
    end

    # The page that asks before an account is deleted says what is strictly private and goes with it (User
    # before_destroy removes it); locking is as before
    module UsersControllerPatch
      def destroy
        if @user && ::GkAccess::Private.holds_strict?(@user)
          held = ::GkAccess::Private.held_back(@user)
          if held.any? && !params[:lock] && (api_request? || params[:confirm] == @user.login)
            return gk_access_refuse(::GkAccess::Private.held_back_message(@user, held), edit_user_path(@user))
          end

          flash.now[:warning] = held.any? ? ::GkAccess::Private.held_back_message(@user, held) : ::GkAccess::Private.deletion_warning(@user)
        end
        super
      end

      def bulk_destroy
        users = ::User.where(id: params[:ids]).to_a.select { |u| ::GkAccess::Private.holds_strict?(u) }
        held = users.select { |u| ::GkAccess::Private.held_back(u).any? }
        if held.any? && params[:confirm].present?
          return gk_access_refuse(held.map { |u| ::GkAccess::Private.held_back_message(u) }.join(' '), users_path)
        end

        flash.now[:warning] = users.map { |u| ::GkAccess::Private.deletion_warning(u) }.join(' ') if users.any?
        super
      end

      private

      def gk_access_refuse(message, back)
        respond_to do |format|
          format.html do
            flash[:error] = message
            redirect_to back
          end
          format.api { render json: { errors: [message] }, status: :unprocessable_entity }
        end
      end
    end

    module MyControllerPatch
      def destroy
        if ::GkAccess::Private.holds_strict?(User.current)
          held = ::GkAccess::Private.held_back(User.current)
          refused = if held.any? then ::GkAccess::Private.held_back_message(User.current, held)
                    elsif ::GkAccess::Private.admin_needed?(User.current) then ::I18n.t(:error_gk_access_user_strict_admin_only)
                    end
          if refused
            flash[:error] = refused
            return redirect_to my_account_path
          end

          flash.now[:warning] = held.any? ? ::GkAccess::Private.held_back_message(User.current, held) : ::GkAccess::Private.deletion_warning(User.current)
        end
        super
      end
    end

    # The tab Private in a project's settings, for those who may manage it (or the administrator), in core_stuff's
    # register project_settings_tab. The register shows the tab to whoever has the permission in the project, which an
    # administrator always has (it is in no project module); the condition here is the rest.
    module ProjectTab
      def self.register!
        unless defined?(::GkCoreStuff::Tabs::PluginDsl)
          ::Rails.logger.warn("[gk_access] gk_core_stuff is missing, although it is required: the tab Private in a project's settings is not shown")
          return
        end

        ::Redmine::Plugin.find(:gk_access).project_settings_tab :gk_access_private, partial: 'gk_access_private_modes/project_tab',
                                                                                    label: :label_gk_access_private, permission: :manage_gk_access_private,
                                                                                    if: ->(c) { c[:project] && ::GkAccess.gui? && ::GkAccess::Private.ready? }
      end
    end
  end
end
