# frozen_string_literal: true

# An information level: a key, a rank (a higher rank is more restricted) and a name in one language. Other languages
# for the name are kept by fields' Translations when fields is there. A default level without a name takes it from
# the locales. A level in use is never removed; it is closed for new things. ApplicationRecord gives the attributes'
# names in errors from the locales (field_gk_access_level_<attribute>, then core's field_<attribute>).
class GkAccessLevel < ApplicationRecord
  self.table_name = 'gk_access_levels'

  has_many :role_levels, class_name: 'GkAccessRoleLevel', foreign_key: :level_id, dependent: :restrict_with_error

  validates :key, presence: true, uniqueness: true, length: { maximum: 40 }, format: { with: /\A[a-z][a-z0-9_]*\z/ }
  validates :rank, presence: true, uniqueness: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :name, length: { maximum: 120 }
  validate :name_when_not_default
  validate :key_kept, on: :update

  scope :sorted, -> { order(:rank) }
  scope :open_for_new, -> { where(closed: false) }

  DEFAULT_KEYS = %w[open internal sensitive].freeze

  def default? = DEFAULT_KEYS.include?(key.to_s)

  def label
    name.presence || ::I18n.t(:"label_gk_access_level_#{key}", default: key.to_s)
  end

  def to_s = label

  def lowest? = GkAccess.lowest&.id == id

  # A level is in use when a role has it as its ceiling or another plugin says it uses it (fields layouts)
  def in_use? = role_levels.exists? || GkAccess.used_elsewhere?(self)

  private

  def name_when_not_default
    errors.add(:name, :blank) if !default? && name.blank?
  end

  def key_kept
    errors.add(:key, :invalid) if key_changed?
  end
end
