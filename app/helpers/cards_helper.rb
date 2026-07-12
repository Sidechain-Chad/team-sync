module CardsHelper
  # Tailwind classes for the due-date pill, by status.
  DUE_PILL_CLASSES = {
    complete: "bg-success-600 text-white",
    overdue:  "bg-danger-600  text-white",
    due_soon: "bg-warn-100    text-warn-700",
    upcoming: "bg-surface-200 text-ink-500",
    none:     "bg-surface-200 text-ink-500"
  }.freeze

  def due_pill_class(card)
    DUE_PILL_CLASSES[card.due_status]
  end

  def due_pill_label(card)
    return nil if card.due_date.blank?
    card.due_date.strftime("%b %-d")
  end

  # The pill's color is the only thing that distinguishes overdue/due-soon/
  # complete/upcoming — this puts the same distinction into words for
  # screen readers (the visible pill only ever shows the date).
  DUE_STATUS_WORDS = {
    complete: "Completed",
    overdue:  "Overdue",
    due_soon: "Due soon",
    upcoming: "Due",
    none:     nil
  }.freeze

  def due_pill_aria_label(card)
    return nil if card.due_date.blank?
    "#{DUE_STATUS_WORDS[card.due_status]}: #{card.due_date.strftime('%b %-d, %Y at %-l:%M %p')}"
  end

  # Format the due date for the <input type="datetime-local"> field.
  # That input requires "YYYY-MM-DDTHH:MM" with no timezone.
  def due_date_for_input(card)
    card.due_date&.strftime("%Y-%m-%dT%H:%M")
  end

  # Cover thumbnail for the board view. :cover is a named, preprocessed
  # variant (see Card) — no `.processed` here, so a variant that isn't
  # ready yet is generated lazily on the image request, not on this render.
  def card_cover_url(card)
    image = card.cover_image
    return nil unless image
    url_for(image.variant(:cover))
  end
end
