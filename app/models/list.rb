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

  # Duplicates this list and its ACTIVE cards onto `board`.
  #
  # Archived cards are deliberately not copied: they're history the source list
  # keeps, and a fresh copy arriving pre-populated with an archive nobody asked
  # for is surprising. (Same instinct as Card#copy_to not copying comments.)
  #
  # `board` is a parameter rather than always `self.board` so board copy can reuse
  # this method wholesale. ListsController#copy only ever passes the SAME board —
  # a cross-board list copy would hit Card#copy_to's label problem with none of
  # board copy's remapping machinery, so it's not offered.
  #
  # POSITION depends on where the copy is going, and it's derived rather than
  # passed so no caller can get it wrong:
  #
  # - SAME board (ListsController#copy) → immediately after the source, via
  #   acts_as_list's insert_at, which shifts the following lists for us. Trello's
  #   behaviour, and the reason it matters here is visibility: appending put the
  #   copy at the far end of the board, off-screen on a board with several lists,
  #   so a user had no evidence the copy had happened at all.
  # - DIFFERENT board (Board#copy_to) → appended, which is what reproduces the
  #   source board's list order, since board copy walks the source's lists in
  #   position order onto an empty board.
  #
  # log_activity: false on every card — see the note above Card#copy_to. Cards
  # come across with labels, members, checklists+items (items reset incomplete)
  # and attachments (the same blobs, no re-upload). Card WATCHERS do not: a watch
  # is a personal subscription, same reasoning as card copy.
  #
  # One transaction for the whole thing, so a failure part-way through can never
  # leave a half-populated list behind.
  def copy_to(board:, name:, user:, label_map: nil)
    copy = nil

    transaction do
      copy = board.lists.create!(name: name.presence || self.name, card_limit: card_limit)

      # acts_as_list's create callback has already appended it; this pulls it up
      # to sit right after the source and shifts everything below down by one.
      # Inside the transaction, so a failure can't leave the copy stranded at the
      # end of the board.
      copy.insert_at(position + 1) if board.id == board_id

      active_cards.each do |card|
        card.copy_to(list: copy, title: card.title, user: user,
                     log_activity: false, label_map: label_map)
      end
    end

    copy
  end

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
