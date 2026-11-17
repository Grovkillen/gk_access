# frozen_string_literal: true

module GkAccess
  class Error < StandardError; end

  # A question about a level that cannot be answered: the levels cannot be read, or the key names no level. Never
  # taken for a yes; the plugin that asks hides what it asked about.
  class Unreadable < Error; end

  # The question other plugins ask: which levels there are, and whether a person sees one.
  # A level is a row with a rank; a higher rank is more restricted, and whoever sees a level sees every level with a
  # lower rank. A role's ceiling is its highest level; without a ceiling a role sees the lowest level only. The
  # administrator sees every level with a rank. Private is outside the ranking: a private note or issue works as in
  # Redmine, or where strict is chosen reaches only the one who wrote it (private.rb).
  module_function

  def ready?
    ::GkAccessLevel.table_exists? && ::GkAccessRoleLevel.table_exists? && ::GkAccessPrivateMode.table_exists?
  rescue StandardError
    false
  end

  # records is required: no level, ceiling or Private changes without its history
  def records? = defined?(::GkRecords::Events) ? true : false

  def records_checked!
    return if records?

    Rails.logger.warn('[gk_access] gk_records is missing: levels, ceilings and Private cannot be changed')
  end

  def require_records!
    raise Error, ::I18n.t(:error_gk_access_records) unless records?
  end

  # Every level, open and closed, by rank
  def levels = ready? ? ::GkAccessLevel.sorted.to_a : []

  # Every level by rank, for a question that must not be answered without them (sees?): raises Unreadable when the
  # tables of the levels and the ceilings are missing, and a failing read raises as it is, never an empty list
  def levels!
    raise Unreadable, 'the levels cannot be read: their tables are missing' unless ::GkAccessLevel.table_exists? && ::GkAccessRoleLevel.table_exists?

    ::GkAccessLevel.sorted.to_a
  end

  def level(key)
    return key if key.is_a?(::GkAccessLevel)
    return nil if key.blank?

    levels.detect { |l| l.key == key.to_s }
  end

  def lowest = levels.first

  # The rank of a level, its key or nil; an unknown key has no rank
  def rank_of(level_or_key) = level(level_or_key)&.rank

  # Of two levels (or keys) the one with the higher rank; an unknown one counts as the lowest
  def stricter(a, b)
    la = level(a) || lowest
    lb = level(b) || lowest
    return la || lb unless la && lb

    lb.rank > la.rank ? lb : la
  end

  # The step of a level above the lowest: 0 for the lowest, 1 for the next and so on (for a style per step)
  def step_of(level_or_key)
    l = level(level_or_key)
    l ? levels.index { |x| x.id == l.id }.to_i : 0
  end

  def ceilings
    ::GkAccessRoleLevel.joins(:level).pluck(:role_id, "#{::GkAccessLevel.table_name}.rank").to_h
  end

  # The roles a person has: in a project, core's roles for the project (Non member and Anonymous included); without
  # a project, every role in any project and the builtin role, as core's allowed_to_globally? reads them
  def roles_of(user, project)
    user ||= ::User.anonymous
    if project
      user.roles_for_project(project).to_a
    else
      roles = user.logged? ? ::Role.joins(:members).where(members: { user_id: [user.id] + user.group_ids }).distinct.to_a : []
      roles << (user.logged? ? ::Role.non_member : ::Role.anonymous)
      roles.uniq
    end
  end

  # The highest rank the person sees; all: the levels by rank, when the caller has already read them
  def ceiling_rank(user, project = nil, all = levels)
    low = all.first&.rank || 0
    user ||= ::User.anonymous
    return all.last&.rank || low if user.admin?

    c = ceilings
    ([low] + roles_of(user, project).map { |r| c[r.id] }.compact).max
  end

  # The highest level the person sees (for the line "You see")
  def ceiling(user, project = nil)
    r = ceiling_rank(user, project)
    levels.reverse.detect { |l| l.rank <= r } || lowest
  end

  # Does this person see this level, in the project or anywhere? The lowest level, and no level (blank), is seen by
  # all who see the thing. When the answer cannot be known it answers no and never yes, and writes the failure to the
  # log: the levels cannot be read (Unreadable, or the failing read's own error), the ceilings cannot be read, or the
  # key names no level (Unreadable). The plugin that asks then hides what it asked about, for everyone while it lasts.
  def sees?(user, level_or_key, project: nil)
    all = levels!
    return true if level_or_key.blank?

    l = level_or_key.is_a?(::GkAccessLevel) ? level_or_key : all.detect { |x| x.key == level_or_key.to_s }
    raise Unreadable, "no level #{level_or_key}" unless l
    return true if l.id == all.first&.id

    l.rank <= ceiling_rank(user, project, all)
  rescue StandardError => e
    Rails.logger&.warn("[gk_access] level not read, taken as not seen: #{e.class} #{e.message}")
    false
  end

  # The levels the person sees, by rank
  def levels_seen(user, project = nil)
    r = ceiling_rank(user, project)
    levels.select { |l| l.rank <= r }
  end

  # Another plugin that keeps levels on its things says whether a level is in use there, so that it is never removed
  def users = (@users ||= {})

  def register_user(key, &block)
    users[key.to_s] = block
  end

  def used_elsewhere?(level)
    users.values.any? do |b|
      b.call(level)
    rescue StandardError
      false
    end
  end

  def write_event(target, kind, details:, user: ::User.current, reason: nil)
    require_records!
    ::GkRecords::Events.write(target, kind, details: details, reason: reason, user: user)
  end

  # Changes of the levels and ceilings, each an event in records
  def save_level!(level, attrs, user: ::User.current)
    require_records!
    before = level.attributes.slice('key', 'rank', 'name', 'closed')
    level.assign_attributes(attrs)
    ::GkAccessLevel.transaction do
      created = level.new_record?
      level.save!
      after = level.attributes.slice('key', 'rank', 'name', 'closed')
      details = after.each_with_object({}) do |(k, v), h|
        next if !created && before[k] == v

        h[k] = [created ? nil : before[k], v]
      end
      write_event(level, 'access.level', details: details, user: user) if details.any?
    end
    level
  end

  DEFAULTS = [['open', 0], ['internal', 100], ['sensitive', 200]].freeze

  # The three defaults, put back where they are missing (a scenario's wipe empties the table); a key or rank already
  # taken is left as it is
  def ensure_defaults!(user: ::User.current)
    return unless ready?

    DEFAULTS.each do |key, rank|
      next if ::GkAccessLevel.exists?(key: key) || ::GkAccessLevel.exists?(rank: rank)

      save_level!(::GkAccessLevel.new, { key: key, rank: rank, closed: false }, user: user)
    end
  end

  def set_ceiling!(role, level, user: ::User.current)
    require_records!
    row = ::GkAccessRoleLevel.find_or_initialize_by(role_id: role.id)
    before = row.level || lowest
    after = level || lowest
    return row if before&.id == after&.id

    # the row stays also when the ceiling is the lowest again: it is the target its history is written on
    ::GkAccessRoleLevel.transaction do
      row.level = after
      row.save!
      write_event(row, 'access.role_level', details: { 'role' => role.name, 'level' => [before&.key, after&.key] }, user: user)
    end
    row
  end

  # The trace in records: the three targets and the five event kinds, nothing that is drawn (the appearance setting
  # is Private.register_hint!). Called whatever the gate to GK GUI Stuff says, so that the protection's own events
  # (access.private on the issue, access.strict_removed) have a target and a kind to be written with. The address of
  # the three targets is the page Administration > Levels, which is closed with the gate: the address asks the gate
  # each time it is read and is nil while the page answers 404, so that nobody gets a link to a closed page.
  def register_records!
    return unless defined?(::GkRecords::Targets)

    admin = ->(_o, u) { u.admin? }
    none = ->(_o, _u) { false }
    page = ->(_o) { GkAccess.gui? ? '/gk_access/levels' : nil }
    ::GkRecords::Targets.register('gk_access_level', model: 'GkAccessLevel', visible: admin, editable: none,
                                                       label: ->(l) { l.label }, url: page)
    ::GkRecords::Targets.register('gk_access_role_level', model: 'GkAccessRoleLevel', visible: admin, editable: none,
                                                            label: ->(r) { r.role&.name.to_s }, url: page)
    ::GkRecords::Targets.register('gk_access_private_mode', model: 'GkAccessPrivateMode', visible: admin, editable: none,
                                                              label: ->(m) { m.label }, url: page)
    ::GkRecords::Kinds.register_event('access.level', plugin: :gk_access, label_key: 'label_gk_access_event_level', target: 'gk_access_level')
    ::GkRecords::Kinds.register_event('access.role_level', plugin: :gk_access, label_key: 'label_gk_access_event_role_level',
                                                           target: 'gk_access_role_level')
    ::GkRecords::Kinds.register_event('access.private_mode', plugin: :gk_access, label_key: 'label_gk_access_event_private_mode',
                                                             target: 'gk_access_private_mode')
    ::GkRecords::Kinds.register_event('access.strict_removed', plugin: :gk_access, label_key: 'label_gk_access_event_strict_removed',
                                                               target: 'gk_access_private_mode')
    ::GkRecords::Kinds.register_event('access.private', plugin: :gk_access, label_key: 'label_gk_access_event_private', target: 'issue')
  end

  # The names of levels the administrator adds are written in one language; fields' Translations keeps the others
  def register_translations!
    return unless defined?(::GkFields::Translations) && ::GkFields::Translations.respond_to?(:register_type)

    ::GkFields::Translations.register_type('GkAccessLevel', attrs: %w[name], label: -> { ::I18n.t(:label_gk_access_levels) },
                                                             records: -> { ::GkAccessLevel.where.not(name: [nil, '']).sorted },
                                                             off_controllers: %w[gk_access_levels])
  end

  # OAuth token scopes on the REST API, through gk_compat when it is there (it is optional). A scope only limits: who
  # may do something is still the same check as on the pages (the admin flag, or Manage Private in a project). Without
  # gk_compat 1.01.000 or later (the scope checks came there) core's own checks apply.
  module ApiScope
    module_function

    # Read the levels, the ceilings, the kinds of Private and the strictly private counts
    READ = :gk_access_api_read
    # Create, change, close and remove levels, change the ceilings and the kinds of Private
    MANAGE = :gk_access_api_manage

    # True without a token; with a token only when it has the permission
    def allows?(user, permission)
      shim?(:scope_allows?) ? ::GkCompat.call(:scope_allows?, user, permission) : true
    end

    # The account is an administrator and the token, if any, has the permission (or :admin)
    def admin_allows?(user, permission)
      shim?(:admin_allows?) ? ::GkCompat.call(:admin_allows?, user, permission) : user.admin?
    end

    # gk_compat is there and has the shim for the running series (an older gk_compat has neither scope check)
    def shim?(name)
      defined?(::GkCompat) && ::GkCompat.respond_to?(:used) && ::GkCompat.used.shims.key?(name)
    end
  end

  # What the REST API answers: the same facts the pages show, never more
  module Api
    module_function

    def level(lv)
      { id: lv.id, key: lv.key, rank: lv.rank, name: lv.name, label: lv.label, closed: lv.closed?, default: lv.default?,
        in_use: lv.in_use? }
    end

    # Every role with its ceiling; a role without a row has the lowest level
    def ceilings
      rows = ::GkAccessRoleLevel.includes(:level).index_by(&:role_id)
      low = GkAccess.lowest
      ::Role.sorted.map do |role|
        lv = rows[role.id]&.level || low
        { role_id: role.id, role: role.name, builtin: role.builtin.to_i.positive?, level: lv&.key }
      end
    end

    # The level a REST call names, by its key or its id
    def level_ref(ref)
      return nil if ref.blank?

      GkAccess.levels.detect { |l| l.key == ref.to_s || l.id.to_s == ref.to_s }
    end

    def mode(row)
      { issues: GkAccess::Private.mode_word(row&.issues_strict?), notes: GkAccess::Private.mode_word(row&.notes_strict?) }
    end

    # The projects that chose strict themselves, as on Administration > Levels
    def strict_projects
      ::GkAccessPrivateMode.where.not(project_id: nil).where('issues_strict = ? OR notes_strict = ?', true, true)
                           .includes(:project).to_a.select(&:project).sort_by { |m| m.project.name }
                           .map { |m| { project_id: m.project_id, identifier: m.project.identifier, name: m.project.name }.merge(mode(m)) }
    end

    def strict_counts
      GkAccess::Private.counts_per_project.map do |project, c|
        { project_id: project.id, identifier: project.identifier, name: project.name, issues: c[:issues], notes: c[:notes] }
      end
    end
  end
end
