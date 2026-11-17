# frozen_string_literal: true

# Administration > Levels: the levels by rank, every role's ceiling, and Private: which kind holds in the instance for
# private issues and private notes, with what becomes strictly private before it is chosen, and the projects that
# have chosen strict themselves. Every change is an event in records; without records nothing is changed.
# REST (.json): the same, for administrators only, as the page. An OAuth token also needs the scope
# gk_access_api_read to read and gk_access_api_manage to change.
class GkAccessLevelsController < ApplicationController
  include GkAccess::Gate::Controller

  layout 'admin'
  self.main_menu = false

  READS = %w[index show ceilings_show private_show strict_counts].freeze

  before_action :require_admin_or_scope
  before_action :find_level, only: [:show, :edit, :update, :destroy]
  accept_api_auth :index, :show, :create, :update, :destroy, :ceilings_show, :ceilings, :private_show, :private_mode,
                  :strict_counts

  def index
    respond_to do |format|
      format.html do
        @levels = GkAccess.levels
        @roles = ::Role.sorted.to_a
        @ceilings = ::GkAccessRoleLevel.pluck(:role_id, :level_id).to_h
        @mode = ::GkAccessPrivateMode.instance_row || ::GkAccessPrivateMode.new
        @inventory = GkAccess::Private.inventory
        @project_modes = ::GkAccessPrivateMode.where.not(project_id: nil).where('issues_strict = ? OR notes_strict = ?', true, true)
                                              .includes(:project).to_a.select(&:project).sort_by { |m| m.project.name }
        @counts = GkAccess::Private.counts_per_project
      end
      format.api { render json: { api_version: 1, levels: GkAccess.levels.map { |lv| GkAccess::Api.level(lv) } } }
    end
  end

  # REST only: one level
  def show
    respond_to do |format|
      format.html { redirect_to edit_gk_access_level_path(@level) }
      format.api { render json: { api_version: 1, level: GkAccess::Api.level(@level) } }
    end
  end

  def new
    top = GkAccess.levels.last
    @level = ::GkAccessLevel.new(rank: top ? top.rank + 100 : 0)
  end

  def create
    @level = ::GkAccessLevel.new
    GkAccess.save_level!(@level, level_params.slice(:key, :rank, :name, :closed))
    return render(json: { api_version: 1, level: GkAccess::Api.level(@level) }, status: :created) if api_request?

    flash[:notice] = l(:notice_successful_create)
    redirect_to gk_access_levels_path
  rescue ActiveRecord::RecordInvalid
    return render_validation_errors(@level) if api_request?

    render :new, status: :unprocessable_entity
  rescue GkAccess::Error => e
    return render_api_errors(e.message) if api_request?

    flash.now[:error] = e.message
    render :new, status: :unprocessable_entity
  end

  def edit; end

  # Closing a level is closed: true; the key never changes
  def update
    GkAccess.save_level!(@level, level_params.slice(:rank, :name, :closed))
    return render(json: { api_version: 1, level: GkAccess::Api.level(@level) }) if api_request?

    flash[:notice] = l(:notice_successful_update)
    redirect_to gk_access_levels_path
  rescue ActiveRecord::RecordInvalid
    return render_validation_errors(@level) if api_request?

    render :edit, status: :unprocessable_entity
  rescue GkAccess::Error => e
    return render_api_errors(e.message) if api_request?

    flash.now[:error] = e.message
    render :edit, status: :unprocessable_entity
  end

  # A level is removed only when nothing uses it and it is not one of the defaults; otherwise it is closed
  def destroy
    if @level.default? || @level.in_use?
      # a default is never removed, used or not
      msg = @level.default? ? l(:error_gk_access_level_default) : l(:error_gk_access_level_in_use)
      return render_api_errors(msg) if api_request?

      flash[:error] = msg
    else
      GkAccess.require_records!
      ::GkAccessLevel.transaction do
        GkAccess.write_event(@level, 'access.level', details: { 'key' => [@level.key, nil], 'rank' => [@level.rank, nil] })
        @level.destroy!
      end
      return render_api_ok if api_request?

      flash[:notice] = l(:notice_successful_delete)
    end
    redirect_to gk_access_levels_path
  rescue GkAccess::Error => e
    return render_api_errors(e.message) if api_request?

    flash[:error] = e.message
    redirect_to gk_access_levels_path
  end

  # REST only: every role with its ceiling (the page shows them on Levels)
  def ceilings_show
    respond_to do |format|
      format.html { redirect_to gk_access_levels_path }
      format.api { render json: { api_version: 1, ceilings: GkAccess::Api.ceilings } }
    end
  end

  def ceilings
    return api_ceilings if api_request?

    levels = GkAccess.levels.index_by { |x| x.id.to_s }
    changed = 0
    ::Role.sorted.each do |role|
      wanted = params.dig(:ceiling, role.id.to_s)
      next if wanted.nil?

      before = ::GkAccessRoleLevel.find_by(role_id: role.id)&.level_id
      level = levels[wanted.to_s] || GkAccess.lowest
      GkAccess.set_ceiling!(role, level)
      changed += 1 if (before || GkAccess.lowest&.id) != level&.id
    end
    flash[:notice] = changed.positive? ? l(:notice_successful_update) : l(:text_gk_access_nothing_changed)
    redirect_to gk_access_levels_path
  rescue GkAccess::Error, ActiveRecord::RecordInvalid => e
    flash[:error] = e.message
    redirect_to gk_access_levels_path
  end

  # REST only: the instance's kind of Private, what becomes strictly private if strict is chosen where it does not hold
  # yet and who loses access, and the projects that chose strict themselves (the box Private on Levels)
  def private_show
    respond_to do |format|
      format.html { redirect_to gk_access_levels_path }
      format.api do
        render json: { api_version: 1, private: GkAccess::Api.mode(::GkAccessPrivateMode.instance_row),
                       inventory: GkAccess::Private.inventory, projects: GkAccess::Api.strict_projects }
      end
    end
  end

  # The instance's kind of Private, for private issues and private notes each
  def private_mode
    return api_private_mode if api_request?

    p = params.fetch(:private, {})
    GkAccess::Private.set_mode!(nil, issues: p[:issues] == 'strict', notes: p[:notes] == 'strict', user: User.current)
    flash[:notice] = l(:notice_successful_update)
    redirect_to gk_access_levels_path
  rescue GkAccess::Error, ActiveRecord::RecordInvalid => e
    flash[:error] = e.message
    redirect_to gk_access_levels_path
  end

  # REST only: how many strictly private issues and notes each project has, never which (the list on Levels)
  def strict_counts
    respond_to do |format|
      format.html { redirect_to gk_access_levels_path }
      format.api { render json: { api_version: 1, counts: GkAccess::Api.strict_counts } }
    end
  end

  private

  # The page is an administrator's (core's require_admin). REST: an administrator, and a token also needs the read or
  # the manage scope (or :admin), so that a token can be narrowed to this API.
  def require_admin_or_scope
    return require_admin unless api_request?
    return false unless require_login

    scope = READS.include?(action_name) ? GkAccess::ApiScope::READ : GkAccess::ApiScope::MANAGE
    return true if GkAccess::ApiScope.admin_allows?(User.current, scope)

    render_403
    false
  end

  # REST: { ceilings: { "<role id>": "<level key or id>" } }; the roles not named keep theirs. Nothing is changed when
  # a role or a level is unknown.
  def api_ceilings
    given = params[:ceilings].respond_to?(:to_unsafe_h) ? params[:ceilings].to_unsafe_h : {}
    roles = ::Role.where(id: given.keys.map(&:to_i)).index_by { |r| r.id.to_s }
    plan = given.map do |rid, ref|
      role = roles[rid.to_s]
      level = GkAccess::Api.level_ref(ref)
      return render_api_errors(l(:error_gk_access_api_ceiling, role: rid, level: ref)) unless role && level

      [role, level]
    end
    ::GkAccessRoleLevel.transaction { plan.each { |role, level| GkAccess.set_ceiling!(role, level) } }
    render json: { api_version: 1, ceilings: GkAccess::Api.ceilings }
  rescue GkAccess::Error, ActiveRecord::RecordInvalid => e
    render_api_errors(e.message)
  end

  # REST: { private: { issues: "strict" | "core", notes: "strict" | "core" } }; a kind not given stays as it is
  def api_private_mode
    row = ::GkAccessPrivateMode.instance_row
    wanted = GkAccess::Private.wanted_kinds(params[:private], row)
    return render_api_errors(l(:error_gk_access_api_private_kind)) unless wanted

    row = GkAccess::Private.set_mode!(nil, issues: wanted[:issues], notes: wanted[:notes], user: User.current)
    render json: { api_version: 1, private: GkAccess::Api.mode(row) }
  rescue GkAccess::Error, ActiveRecord::RecordInvalid => e
    render_api_errors(e.message)
  end

  def find_level
    @level = ::GkAccessLevel.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  # REST: a body without { "level": { ... } } is refused with core's 422, never Rails' 400
  def level_params
    raw = params[:level]
    unless raw.is_a?(ActionController::Parameters)
      raise GkAccess::Error, l(:error_gk_access_api_level_body) if api_request?

      raw = ActionController::Parameters.new
    end
    p = raw.permit(:key, :rank, :name, :closed)
    # the form's check box ('0', '1') and REST's true and false
    p[:closed] = ActiveModel::Type::Boolean.new.cast(p[:closed]) == true if p.key?(:closed)
    p
  end
end
