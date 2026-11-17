# frozen_string_literal: true

require 'securerandom'

# A private issue (item_type Issue) or private note (item_type Journal) that is strictly private, for good: only its
# author sees it, and only its author ends it by making it not private. The token is its anonymous identity
# (SP-XXXX-XXXX), drawn at random and never derived from the id, so that it cannot be traced back to the thing: the
# only name the administrator, the log and an annulment see for it.
class GkAccessStrictItem < ApplicationRecord
  self.table_name = 'gk_access_strict_items'

  TYPES = { issues: 'Issue', notes: 'Journal' }.freeze
  # no 0/O, 1/I/L: read aloud and copied by hand
  ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'.chars.freeze

  before_validation { self.token ||= self.class.new_token }

  validates :item_type, inclusion: { in: TYPES.values }
  validates :item_id, presence: true, uniqueness: { scope: :item_type }
  validates :token, presence: true, uniqueness: true

  def self.type_of(kind) = TYPES.fetch(kind.to_sym)

  def self.new_token
    loop do
      t = "SP-#{Array.new(4) { ALPHABET[SecureRandom.random_number(ALPHABET.size)] }.join}-" \
          "#{Array.new(4) { ALPHABET[SecureRandom.random_number(ALPHABET.size)] }.join}"
      return t unless exists?(token: t)
    end
  end
end
