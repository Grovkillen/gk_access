# frozen_string_literal: true

# A role's ceiling: the highest level the role sees. Without a row the role sees the lowest level only.
class GkAccessRoleLevel < ApplicationRecord
  self.table_name = 'gk_access_role_levels'

  belongs_to :role, class_name: 'Role'
  belongs_to :level, class_name: 'GkAccessLevel'

  validates :role_id, presence: true, uniqueness: true
  validates :level_id, presence: true
end
