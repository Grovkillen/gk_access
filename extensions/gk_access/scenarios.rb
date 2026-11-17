# frozen_string_literal: true

module GkAccess
  # access in scenarios: a step that gives roles their ceilings from the scenario's data (access: ceilings:
  # [{ role:, level: }]) and the kind of Private (access: private: { issues: strict, notes: strict, projects:
  # [{ project:, issues:, notes: }] }; without it Private works as in Redmine); and expectations that make their own
  # people, roles and project, prove the rule, and keep nothing (rolled back). A check of permissions never uses the
  # scenario's own roles: basic's manager has every permission and so every new one.
  # gk_scenarios loads this file and calls register_scenarios! once every plugin is in; the plugin never loads it, so
  # the scenario code is never loaded in production.
  def self.register_scenarios! = Scenarios.register!

  module Scenarios
    module_function

    # Own people, roles and a project for one check, inside the check's transaction
    class Kit
      attr_reader :tag, :project, :tracker

      def initialize(name)
        @tag = "#{name}#{::Time.current.strftime('%H%M%S')}#{rand(1000)}"
        @tracker = ::Tracker.sorted.first
        @project = ::Project.create!(name: "gk_access #{@tag}", identifier: "accchk-#{@tag}".downcase.tr('_', '-'), is_public: false,
                                     enabled_module_names: %w[issue_tracking], trackers: [@tracker])
      end

      def role(key, permissions, visibility = 'default')
        ::Role.create!(name: "gk_access #{@tag} #{key}", permissions: permissions, issues_visibility: visibility, assignable: true)
      end

      def user(key, admin: false)
        u = ::User.new(firstname: 'Acc', lastname: "#{key} #{@tag}", mail: "accchk.#{key}.#{@tag}@example.net".downcase, language: 'en')
        u.login = "accchk_#{key}_#{@tag}".downcase
        u.admin = admin
        u.status = ::User::STATUS_ACTIVE
        u.save!
        u
      end

      def member(principal, role)
        ::Member.create!(project: @project, principal: principal, roles: [role])
      end

      def issue(author, attrs = {})
        ::Issue.create!({ project: @project, tracker: @tracker, author: author, subject: "gk_access #{@tag}",
                          priority: ::IssuePriority.default || ::IssuePriority.active.first }.merge(attrs))
      end

      # The kit's project strict (or not) for issues and notes, written directly, and what is private there already
      # marked, as set_mode! does: the check is rolled back
      def strict!(issues: true, notes: true)
        row = ::GkAccessPrivateMode.find_or_initialize_by(project_id: @project.id)
        row.update!(issues_strict: issues, notes_strict: notes, updated_at: ::Time.current)
        ::GkAccess::Private.mark_place!(:issues, @project) if issues
        ::GkAccess::Private.mark_place!(:notes, @project) if notes
      end

      # On a freshly read issue: init_journal keeps the issue's earlier journal when it has one
      def note(issue, by, text, private_notes: true)
        fresh = ::Issue.find(issue.id)
        fresh.init_journal(by, text)
        fresh.private_notes = private_notes
        fresh.save!
        fresh.journals.order(:id).last
      end
    end

    def as(user)
      prev = ::User.current
      ::User.current = user
      yield
    ensure
      ::User.current = prev
    end

    def checked(failed)
      { 'ok' => failed.empty?, 'want' => 'holds', 'got' => failed.empty? ? 'holds' : "not: #{failed.join(', ')}" }
    end

    # The check's transaction, rolled back, so that no level, ceiling or kind of Private it made is left
    def rolled_back
      out = nil
      ::ActiveRecord::Base.transaction do
        out = yield
        raise ::ActiveRecord::Rollback
      end
      out
    rescue StandardError => e
      # the report then says where in the check it fell, not only what
      at = Array(e.backtrace).detect { |l| l.include?('gk_access') }.to_s.split(%r{[/\\]}).last
      raise "#{e.class}: #{e.message} (#{at})"
    ensure
      ::GkAccess::Private.reset!
    end

    def register!
      return unless defined?(::GkScenarios::Steps)

      ::GkScenarios::Steps.register('access', plugin: :gk_access, order: 150) do |ctx|
        next unless ::GkAccess.ready?

        ::GkAccess.ensure_defaults! if ::GkAccess.records?
        data = ctx.scenario.data['access'] || {}
        priv = data['private'] || {}
        strict = ->(h, k) { h[k].to_s == 'strict' }
        if priv.key?('issues') || priv.key?('notes')
          ::GkAccess::Private.set_mode!(nil, issues: strict.(priv, 'issues'), notes: strict.(priv, 'notes'))
          ctx.note(:access_private, 'instance', ::GkAccessPrivateMode.instance_row, true)
        end
        Array(priv['projects']).each do |row|
          project = ctx.get(:project, row['project'])
          ::GkAccess::Private.set_mode!(project, issues: strict.(row, 'issues'), notes: strict.(row, 'notes'))
          ctx.note(:access_private, row['project'], ::GkAccessPrivateMode.find_by(project_id: project.id), true)
        end
        Array(data['ceilings']).each do |row|
          role = ctx.get(:role, row['role'])
          level = ::GkAccess.level(row['level']) or raise ::GkScenarios::Error, ::I18n.t(:error_gk_access_scenario_level, level: row['level'])
          before = ::GkAccessRoleLevel.find_by(role_id: role.id)&.level_id
          ::GkAccess.set_ceiling!(role, level)
          ctx.note(:access_ceiling, row['role'], role, before != level.id)
        end
      end

      # access_levels: true: the levels are data with a rank; a level between two is put in its place, a closed one
      # stays, a key is kept; a role's ceiling gives the levels up to it in its project and nowhere else; the builtin
      # roles have ceilings like the others; the administrator sees every level.
      ::GkScenarios::Expect.register('access_levels') do |_ctx, _e|
        failed = []
        rolled_back do
          keys = ::GkAccess.levels.map(&:key)
          failed << "defaults (#{keys.join(' ')})" unless (%w[open internal sensitive] - keys).empty?
          failed << 'lowest_open' unless ::GkAccess.lowest&.key == 'open'
          mid = ::GkAccess.save_level!(::GkAccessLevel.new, { key: 'accchk_mid', rank: 150, name: 'Mid' })
          order = ::GkAccess.levels.map(&:key)
          failed << 'between' unless order.index('accchk_mid') == order.index('internal') + 1
          failed << 'no_name_refused' if ::GkAccessLevel.new(key: 'accchk_noname', rank: 160).valid?
          failed << 'rank_twice_refused' if ::GkAccessLevel.new(key: 'accchk_twice', rank: 150, name: 'Twice').valid?
          ::GkAccess.save_level!(mid, { closed: true })
          failed << 'closed_kept' unless ::GkAccess.level('accchk_mid')&.closed?
          mid.key = 'other'
          failed << 'key_kept' if mid.valid?
          mid.reload

          kit = Kit.new('lv')
          other = Kit.new('lv2')
          seer = kit.role('seer', %i[view_issues])
          plain = kit.role('plain', %i[view_issues])
          u = kit.user('seer')
          v = kit.user('plain')
          admin = kit.user('admin', admin: true)
          kit.member(u, seer)
          kit.member(v, plain)
          ::GkAccess.set_ceiling!(seer, ::GkAccess.level('sensitive'))
          failed << 'sees_sensitive' unless ::GkAccess.sees?(u, 'sensitive', project: kit.project)
          failed << 'sees_lower' unless ::GkAccess.sees?(u, 'accchk_mid', project: kit.project)
          failed << 'not_elsewhere' if ::GkAccess.sees?(u, 'sensitive', project: other.project)
          failed << 'globally' unless ::GkAccess.sees?(u, 'sensitive')
          failed << 'plain_not' if ::GkAccess.sees?(v, 'internal', project: kit.project)
          failed << 'plain_lowest' unless ::GkAccess.sees?(v, 'open', project: kit.project)
          failed << "ceiling (#{::GkAccess.ceiling(u, kit.project)&.key})" unless ::GkAccess.ceiling(u, kit.project)&.key == 'sensitive'
          failed << 'admin_all' unless ::GkAccess.sees?(admin, 'sensitive', project: kit.project)
          before_nm = ::GkAccessRoleLevel.find_by(role_id: ::Role.non_member.id)&.level
          ::GkAccess.set_ceiling!(::Role.non_member, ::GkAccess.level('internal'))
          kit.project.update!(is_public: true)
          outsider = kit.user('outsider')
          failed << 'non_member' unless ::GkAccess.sees?(outsider, 'internal', project: kit.project)
          ::GkAccess.set_ceiling!(::Role.non_member, before_nm)
          failed << 'anonymous' if ::GkAccess.sees?(::User.anonymous, 'internal', project: kit.project)
        end
        checked(failed)
      end

      # access_private_note: true: as in Redmine (the default) a private note reaches its author, roles with View
      # private notes and the administrator, and the line by it says so with the role's name. With strict notes in the
      # project it reaches only its author, in every channel core has: the issue's history, Journal.visible (lists,
      # queries, Atom), Journal#visible?, the search, last updated by and the mail's recipients. A reader with View
      # private notes and issue visibility all, a watcher, the assignee and the administrator do not reach it. Under
      # strict a note with changes cannot be made private afterwards, and only its author makes a note private.
      ::GkScenarios::Expect.register('access_private_note') do |_ctx, _e|
        failed = []
        rolled_back do
          kit = Kit.new('pn')
          writer = kit.role('writer', %i[view_issues add_issues edit_issues add_issue_notes set_notes_private view_private_notes
                                         add_issue_watchers view_issue_watchers])
          reader = kit.role('reader', %i[view_issues view_private_notes set_notes_private add_issue_notes], 'all')
          author = kit.user('author')
          other = kit.user('reader')
          assignee = kit.user('assignee')
          watcher = kit.user('watcher')
          admin = kit.user('admin', admin: true)
          kit.member(author, writer)
          [other, assignee, watcher].each { |x| kit.member(x, reader) }
          issue = kit.issue(author, assigned_to: assignee)
          issue.add_watcher(watcher)
          needle = "accchk#{kit.tag}hidden".downcase
          j = as(author) { kit.note(issue, author, "a private note #{needle}") }
          failed << 'note_private' unless j.private_notes?
          seen = ->(u) { issue.reload.visible_journals_with_index(u).map(&:id).include?(j.id) }
          # as in Redmine: the roles with View private notes and the administrator reach it
          failed << 'core_not_strict' if ::GkAccess::Private.strict?(:notes, kit.project)
          { 'reader' => other, 'admin' => admin }.each do |who, u|
            failed << "core_#{who}_history" unless seen.call(u)
            failed << "core_#{who}_scope" unless ::Journal.visible(u).where(id: j.id).exists?
            failed << "core_#{who}_visible" unless j.visible?(u)
          end
          core = as(author) { ::GkAccess::Private.explain(:notes, kit.project, author: author) }
          failed << 'core_explained' unless !core[:strict] && core[:text].include?(reader.name)
          kit.strict!(issues: false, notes: true)
          failed << 'strict_now' unless ::GkAccess::Private.strict?(:notes, kit.project)
          strict = as(author) { ::GkAccess::Private.explain(:notes, kit.project, author: author) }
          failed << 'strict_explained' unless strict[:strict] && !strict[:text].include?(reader.name)
          failed << 'author_history' unless seen.call(author)
          failed << 'author_scope' unless ::Journal.visible(author).where(id: j.id).exists?
          failed << 'author_search' unless ::Issue.search_result_ranks_and_ids([needle], author).map(&:last).include?(issue.id)
          { 'reader' => other, 'assignee' => assignee, 'watcher' => watcher, 'admin' => admin }.each do |who, u|
            failed << "#{who}_history" if seen.call(u)
            failed << "#{who}_scope" if ::Journal.visible(u).where(id: j.id).exists?
            failed << "#{who}_visible" if j.visible?(u)
            failed << "#{who}_search" if ::Issue.search_result_ranks_and_ids([needle], u).map(&:last).include?(issue.id)
            last = as(u) { ::Issue.find(issue.id).last_updated_by }
            failed << "#{who}_last_updated_by" if last&.id == author.id
          end
          rcpt = (j.notified_users | j.notified_watchers | j.notified_mentions).map(&:id)
          failed << "recipients (#{rcpt.size})" if rcpt.any?
          failed << 'mail_patch' unless ::Mailer.singleton_class < ::GkAccess::Private::MailerClassPatch

          # made private afterwards: a note with a change is refused, and only the author changes it
          prev = ::User.current
          ::User.current = author
          fresh = ::Issue.find(issue.id)
          fresh.init_journal(author, "public #{needle}")
          fresh.subject = "#{fresh.subject} changed"
          fresh.save!
          pub = fresh.journals.order(:id).last
          pub.private_notes = true
          if pub.details.any? && pub.valid?
            failed << "with_details_refused (journal #{pub.id}, details #{pub.details.size}, change #{pub.will_save_change_to_private_notes?.inspect}, " \
                      "mine #{::GkAccess::Private.mine?(::User.current, pub.user_id)}, strict #{::GkAccess::Private.strict?(:notes, kit.project)})"
          end
          ::User.current = other
          j.reload.private_notes = false
          failed << 'owner_only' if j.valid?
          ::User.current = prev
        end
        checked(failed)
      end

      # access_private_issue: true: as in Redmine (the default) a private issue reaches its author, a role with issue
      # visibility all and the administrator, it can be assigned to a group, and the line on it names the role. With
      # strict issues in the project it reaches only its author: Issue.visible, Issue#visible? and the recipients. A
      # role with issue visibility all, a group the issue was assigned to before and the administrator do not reach it.
      # It cannot be assigned to anyone but its author; only the author ends Private, and that is an event in records.
      ::GkScenarios::Expect.register('access_private_issue') do |_ctx, _e|
        failed = []
        rolled_back do
          kit = Kit.new('pi')
          writer = kit.role('writer', %i[view_issues add_issues edit_issues set_own_issues_private set_issues_private])
          all = kit.role('all', %i[view_issues edit_issues set_issues_private], 'all')
          author = kit.user('author')
          seer = kit.user('all')
          admin = kit.user('admin', admin: true)
          kit.member(author, writer)
          kit.member(seer, all)
          group = ::Group.create!(lastname: "gk_access #{kit.tag}")
          group.users << seer
          kit.member(group, all)
          prev = ::User.current
          ::User.current = author
          issue = kit.issue(author, is_private: true)
          ::User.current = prev
          # as in Redmine: the role with issue visibility all and the administrator reach it, and someone else may be
          # assigned (whether a group may is core's own setting)
          failed << 'core_not_strict' if ::GkAccess::Private.strict?(:issues, kit.project)
          { 'all' => seer, 'admin' => admin }.each do |who, u|
            failed << "core_#{who}_scope" unless ::Issue.visible(u).where(id: issue.id).exists?
            failed << "core_#{who}_visible" unless issue.visible?(u)
          end
          issue.assigned_to = seer
          failed << "core_assign_other (#{issue.errors.full_messages.join('; ')})" unless issue.valid?
          issue.reload
          core = as(author) { ::GkAccess::Private.explain(:issues, kit.project, author: author) }
          failed << 'core_explained' unless !core[:strict] && core[:text].include?(all.name)
          kit.strict!(issues: true, notes: false)
          failed << 'strict_now' unless ::GkAccess::Private.strict?(:issues, kit.project)
          strict = as(author) { ::GkAccess::Private.explain(:issues, kit.project, author: author) }
          failed << 'strict_explained' unless strict[:strict] && !strict[:text].include?(all.name)
          failed << 'author_scope' unless ::Issue.visible(author).where(id: issue.id).exists?
          failed << 'author_visible' unless issue.visible?(author)
          { 'all' => seer, 'admin' => admin }.each do |who, u|
            failed << "#{who}_scope" if ::Issue.visible(u).where(id: issue.id).exists?
            failed << "#{who}_visible" if issue.visible?(u)
          end
          failed << 'recipients' if (issue.notified_users | issue.notified_watchers).any? { |u| u.id != author.id }
          # Private goes before See as (gk_people): while an administrator looks as the author, her private issue is
          # not shown, neither by visible? nor in the list's scope
          if defined?(::GkPeople::SeeAs)
            key = ::GkPeople::SeeAs::THREAD_KEY
            was = ::Thread.current[key]
            begin
              ::Thread.current[key] = { viewer: author, record: nil }
              failed << 'see_as_visible' if issue.visible?(author)
              failed << 'see_as_scope' if ::Issue.visible(author).where(id: issue.id).exists?
            ensure
              ::Thread.current[key] = was
            end
            failed << 'see_as_ended' unless issue.visible?(author)
          end
          issue.assigned_to = group
          failed << 'assign_refused' if issue.valid?
          issue.reload
          ::User.current = seer
          issue.is_private = false
          failed << 'owner_only' if issue.valid?
          issue.reload
          ::User.current = author
          issue.is_private = false
          issue.save!
          ::User.current = prev
          failed << 'shared_seen' unless issue.reload.visible?(seer)
          if ::GkAccess.records?
            ev = ::GkRecordsEvent.where(target_type: 'issue', target_id: issue.id, kind: 'access.private').exists?
            failed << 'records_event' unless ev
          end
        end
        checked(failed)
      end

      # access_private_modes: true: the choice of kind and the marks. Without a choice Private works as in Redmine
      # everywhere. A project made strict for issues is strict there and nowhere else, and its notes stay as in
      # Redmine; the inventory before counts its private issues and names the role and the assignee who lose access,
      # and the issue is marked. The role that would have seen it is told it is there and strictly private; someone
      # outside the project is not. Only an administrator makes the project less strict again, and then the marked
      # issue stays strict while a new private issue is as in Redmine. The instance made strict for notes holds in
      # every project. Every change is an event in records. An account that is deleted takes its strictly private
      # issue with it and leaves its ordinary private one to Anonymous, as core does.
      ::GkScenarios::Expect.register('access_private_modes') do |_ctx, _e|
        failed = []
        rolled_back do
          ::GkAccessPrivateMode.delete_all
          kit = Kit.new('md')
          other = Kit.new('md2')
          reader = kit.role('reader', %i[view_issues add_issues edit_issues view_private_notes add_issue_notes set_notes_private set_issues_private], 'all')
          author = kit.user('author')
          seer = kit.user('reader')
          manager = kit.user('manager')
          admin = kit.user('admin', admin: true)
          [author, seer, manager].each { |x| kit.member(x, reader) }
          issue = as(author) { kit.issue(author, is_private: true, assigned_to: seer) }
          %i[issues notes].each { |k| failed << "default_core_#{k}" if ::GkAccess::Private.strict?(k, kit.project) }
          failed << 'core_seen' unless ::Issue.visible(seer).where(id: issue.id).exists?
          inv = ::GkAccess::Private.inventory(kit.project, [:issues])
          failed << "counted (#{inv['private_issues']})" unless inv['private_issues'] == 1
          failed << 'role_named' unless inv['losing'].any? { |x| x['kind'] == 'issues_all' && x['name'] == reader.name }
          failed << 'assignee_named' unless inv['losing'].any? { |x| x['kind'] == 'assigned' && x['name'] == seer.name }
          if ::GkAccess.records?
            events = -> { ::GkRecordsEvent.where(kind: 'access.private_mode').count }
            before = events.call
            ::GkAccess::Private.set_mode!(kit.project, issues: true, notes: false, user: manager)
            failed << 'project_issues_strict' unless ::GkAccess::Private.strict?(:issues, kit.project)
            failed << 'project_notes_core' if ::GkAccess::Private.strict?(:notes, kit.project)
            failed << 'other_project_core' if ::GkAccess::Private.strict?(:issues, other.project)
            failed << 'instance_core' if ::GkAccess::Private.instance_strict?(:issues)
            failed << 'marked' unless ::GkAccess::Private.marked?(issue)
            failed << 'strict_hidden' if ::Issue.visible(seer).where(id: issue.id).exists?
            failed << 'strict_hidden_visible' if issue.reload.visible?(seer)
            failed << 'author_still' unless issue.visible?(author)
            failed << 'told_exists' unless ::GkAccess::Private.hidden_by_strict?(issue, seer)
            outsider = other.user('outsider')
            failed << 'outsider_not_told' if ::GkAccess::Private.hidden_by_strict?(issue, outsider)
            hint = as(seer) { ::GkAccess::Private.explain(:issues, kit.project, item: issue, author: author) }
            failed << 'hint_strict' unless hint[:strict]
            begin
              ::GkAccess::Private.set_mode!(kit.project, issues: false, notes: false, user: manager)
              failed << 'loosen_refused'
            rescue ::GkAccess::Error
              nil
            end
            failed << 'still_strict' unless ::GkAccess::Private.strict?(:issues, kit.project)
            ::GkAccess::Private.set_mode!(kit.project, issues: false, notes: false, user: admin)
            failed << 'admin_loosened' if ::GkAccess::Private.strict?(:issues, kit.project)
            # never back to ordinary private: the marked issue stays strict, a new private one is as in Redmine
            failed << 'stays_marked' unless ::GkAccess::Private.marked?(issue)
            failed << 'stays_hidden' if ::Issue.visible(seer).where(id: issue.id).exists?
            failed << 'stays_hint_strict' unless as(seer) { ::GkAccess::Private.explain(:issues, kit.project, item: issue.reload, author: author) }[:strict]
            fresh = as(author) { kit.issue(author, is_private: true) }
            failed << 'new_not_marked' if ::GkAccess::Private.marked?(fresh)
            failed << 'new_seen' unless ::Issue.visible(seer).where(id: fresh.id).exists?
            ::GkAccess::Private.set_mode!(nil, issues: false, notes: true, user: admin)
            failed << 'instance_notes' unless ::GkAccess::Private.strict?(:notes, other.project) && ::GkAccess::Private.strict?(:notes, kit.project)
            failed << 'instance_issues_core' if ::GkAccess::Private.strict?(:issues, other.project)
            made = events.call - before
            failed << "events (#{made})" unless made == 3

            # an account deleted takes its strictly private issue with it; its ordinary private one goes to Anonymous
            holder = other.user('holder')
            other.member(holder, reader)
            other.strict!(issues: true, notes: false)
            gone = as(holder) { other.issue(holder, is_private: true) }
            other.strict!(issues: false, notes: false)
            kept = as(holder) { other.issue(holder, is_private: true) }
            failed << 'holder_marked' unless ::GkAccess::Private.marked?(gone) && !::GkAccess::Private.marked?(kept)
            warning = ::GkAccess::Private.deletion_warning(holder)
            token = ::GkAccess::Private.token_for(gone)
            failed << 'token' unless token.to_s.match?(/\ASP-[A-Z2-9]{4}-[A-Z2-9]{4}\z/)
            failed << 'warned_anonymously' unless warning.include?(token.to_s) && !warning.include?(gone.subject) && !warning.include?("##{gone.id}")
            if defined?(::GkRetention) && ::GkRetention.respond_to?(:summary)
              summary = ::GkRetention.summary(gone)
              failed << "retention_anonymous (#{summary})" unless summary.include?(token.to_s) && !summary.include?(gone.subject) && !summary.include?("##{gone.id}")
            end
            # with GK Retention only an administrator removes for good: the holder may not delete her own account
            failed << 'self_needs_admin' if defined?(::GkRetention) && !::GkAccess::Private.admin_needed?(holder, holder)
            failed << 'admin_may' if ::GkAccess::Private.admin_needed?(holder, admin)
            removed_before = ::GkRecordsEvent.where(kind: 'access.strict_removed').count
            as(admin) { holder.reload.destroy }
            failed << 'strict_removed' if ::Issue.exists?(gone.id)
            failed << 'mark_removed' if ::GkAccessStrictItem.where(item_type: 'Issue', item_id: gone.id).exists?
            failed << 'ordinary_kept' unless ::Issue.exists?(kept.id) && ::Issue.find(kept.id).author&.anonymous?
            failed << 'removed_event' unless ::GkRecordsEvent.where(kind: 'access.strict_removed').count == removed_before + 1
            ev = ::GkRecordsEvent.where(kind: 'access.strict_removed').order(:id).last
            text = ev ? ev.attributes.values.join(' ') : ''
            failed << 'event_anonymous' unless text.include?(token.to_s) && !text.include?(gone.subject) && !text.include?(holder.login)
          end
        end
        checked(failed)
      end
    end
  end
end
