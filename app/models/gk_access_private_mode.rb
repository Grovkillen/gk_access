# frozen_string_literal: true

# Which kind of Private holds, for private issues and private notes each: as in Redmine or strict. The row without a
# project is the instance's choice; a project's own row can only make it stricter there.
class GkAccessPrivateMode < ApplicationRecord
  self.table_name = 'gk_access_private_modes'

  belongs_to :project, optional: true

  validates :project_id, uniqueness: true, allow_nil: true

  def self.instance_row = find_by(project_id: nil)

  def instance? = project_id.nil?

  def strict?(kind) = kind.to_sym == :notes ? notes_strict? : issues_strict?

  def label
    instance? ? ::I18n.t(:label_gk_access_private_instance) : project&.name.to_s
  end
end
