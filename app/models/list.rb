class List < ApplicationRecord
  belongs_to :board
  has_many :cards, -> { order(position: :asc) }, dependent: :destroy
  has_many :active_cards,   -> { active.order(position: :asc) },   class_name: 'Card'
  has_many :archived_cards, -> { archived.order(updated_at: :desc) }, class_name: 'Card'

  validates :name, presence: true

  # Soft WIP limit. nil = no limit (the default for every existing list);
  # any set value must be a positive integer. Nothing enforces it on card
  # creation — Trello doesn't either, and a hard block would fight the
  # gap-inserter and the copy/move paths. It only drives the header pill.
  validates :card_limit, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  # Scope ordering to a single board so insert_at / position shifts
  # only affect lists on the same board, not every list in the DB.
  acts_as_list scope: :board

  # The three list-menu sort options. Values are keys, never interpolated
  # SQL — SORTS[key] is the only way a sort reaches the DB, so an unknown
  # or tampered key resolves to nil and the controller rejects it.
  #
  # NULLS LAST on due_date: cards with no due date sort to the bottom
  # rather than the top. LOWER(title) so "Apple"/"apple" don't depend on
  # the database's collation for a user-visible A→Z ordering.
  SORTS = {
    "due_date" => Arel.sql("due_date ASC NULLS LAST, id ASC"),
    "title"    => Arel.sql("LOWER(title) ASC, id ASC"),
    "newest"   => Arel.sql("created_at DESC, id DESC")
  }.freeze

  def card_limit?
    card_limit.present?
  end

  # Counted against ACTIVE cards only — archiving a card should take a list
  # back under its limit, same as deleting one.
  def over_card_limit?
    card_limit? && active_cards.size > card_limit
  end

  # Sorts the list's active cards by one of SORTS and renumbers position
  # sequentially, so the order sticks across reloads. A one-time reorder,
  # not a sticky mode.
  #
  # Archived cards are renumbered onto the tail rather than left where they
  # were: position is a raw column shared by active AND archived cards in
  # the same acts_as_list scope (see CardsController#bottom_position), so
  # renumbering only the active ones would leave duplicate positions behind.
  # Uses update_column to skip acts_as_list's own callbacks (which would
  # fight the renumbering) and to leave updated_at alone — the archive page
  # orders by updated_at, and a sort isn't a change to an archived card.
  def sort_cards!(key)
    order = SORTS[key]
    return false unless order

    transaction do
      ordered = cards.active.reorder(order).to_a + cards.archived.reorder(position: :asc).to_a
      ordered.each_with_index { |card, index| card.update_column(:position, index + 1) }
    end

    true
  end
end
