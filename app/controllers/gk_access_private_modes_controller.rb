# frozen_string_literal: true

# A project's own kind of Private (the tab Private in its settings): strict for private issues or private notes there,
# never less strict than the instance. Whoever may manage it makes it stricter; only an administrator makes it less
# strict again. Every change is an event in records.
# REST (.json): the same, for whoever sees the tab. An OAuth token also needs the scope gk_access_api_read to read and
# gk_access_api_manage to change, besides Manage Private, which core asks of a token itself (an administrator's token
# needs only the scope).
# While Private's tables cannot be read nothing here answers or changes: REST says so instead of guessing, and the page
# goes back to the project's settings, where the tab is hidden then.
class GkAccessPrivateModesController < ApplicationController
  include GkAccess::Gate::Controller

  before_action -> { require_scope(GkAccess::ApiScope::READ) }, only: [:show]
  before_action -> { require_scope(GkAccess::ApiScope::MANAGE) }, only: [:update]
  before_action :find_project_by_project_id
  before_action :authorize_private
  before_action :require_private_readable
  accept_api_auth :show, :update

  # REST only: the project's own kind, the instance's, and what becomes strictly private here if strict is chosen
  # where it does not hold yet, with who loses access (the tab Private)
  def show
    respond_to do |format|
      format.html { redirect_to settings_project_path(@project, tab: 'gk_access_private') }
      format.api do
        body = private_body
        body ? render(json: body) : render_api_errors(l(:error_gk_access_private_unreadable))
      end
    end
  end

  def update
    return api_update if api_request?

    p = params.fetch(:private, {})
    GkAccess::Private.set_mode!(@project, issues: p[:issues] == 'strict', notes: p[:notes] == 'strict', user: User.current)
    flash[:notice] = l(:notice_successful_update)
    redirect_to settings_project_path(@project, tab: 'gk_access_private')
  rescue GkAccess::Error, ActiveRecord::RecordInvalid => e
    flash[:error] = e.message
    redirect_to settings_project_path(@project, tab: 'gk_access_private')
  end

  private

  # The answer to show, read and never guessed; nil (with the failure in the log) when Private cannot be read
  def private_body
    GkAccess::Private.when_read('not answered') do
      own = ::GkAccessPrivateMode.find_by(project_id: @project.id)
      instance = ::GkAccessPrivateMode.instance_row
      { api_version: 1, project_id: @project.id, identifier: @project.identifier,
        private: GkAccess::Api.mode(own), instance: GkAccess::Api.mode(instance),
        holds: { issues: GkAccess::Private.mode_word(GkAccess::Private.strict_read?(:issues, @project)),
                 notes: GkAccess::Private.mode_word(GkAccess::Private.strict_read?(:notes, @project)) },
        inventory: GkAccess::Private.inventory(@project) }
    end
  end

  def require_private_readable
    return if GkAccess::Private.ready?
    return render_api_errors(l(:error_gk_access_private_unreadable)) if api_request?

    flash[:error] = l(:error_gk_access_private_unreadable)
    redirect_to settings_project_path(@project)
  end

  # REST: { private: { issues: "strict" | "core", notes: "strict" | "core" } }; a kind not given stays as it is
  def api_update
    row = ::GkAccessPrivateMode.find_by(project_id: @project.id)
    wanted = GkAccess::Private.wanted_kinds(params[:private], row)
    return render_api_errors(l(:error_gk_access_api_private_kind)) unless wanted

    row = GkAccess::Private.set_mode!(@project, issues: wanted[:issues], notes: wanted[:notes], user: User.current,
                                                may_loosen: api_admin?)
    render json: { api_version: 1, project_id: @project.id, identifier: @project.identifier, private: GkAccess::Api.mode(row) }
  rescue GkAccess::Error, ActiveRecord::RecordInvalid => e
    render_api_errors(e.message)
  end

  # Manage Private in the project, as core asks it: an administrator passes, but nobody in an archived or a closed
  # project (core's Settings are closed there too). REST: an administrator's token with this API's scope but without
  # :admin is an administrator here as on the instance's REST (with gk_compat 1.01.000 or later).
  def authorize_private
    return if User.current.allowed_to?(:manage_gk_access_private, @project)
    return if api_admin? && @project.allows_to?(:manage_gk_access_private)

    deny_access
  end

  # REST: the account is an administrator and the token, if any, has this action's scope (or :admin)
  def api_admin?
    return false unless api_request?

    GkAccess::ApiScope.admin_allows?(User.current, action_name == 'show' ? GkAccess::ApiScope::READ : GkAccess::ApiScope::MANAGE)
  end

  # REST only (the page has no token); true without a token or without compat
  def require_scope(permission)
    render_403 if api_request? && !GkAccess::ApiScope.allows?(User.current, permission)
  end
end
