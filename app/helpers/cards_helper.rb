module CardsHelper
  # Tailwind classes for the due-date pill, by status.
  DUE_PILL_CLASSES = {
    complete: "bg-green-500 text-white",
    overdue:  "bg-red-500   text-white",
    due_soon: "bg-yellow-400 text-yellow-900",
    upcoming: "bg-gray-200  text-gray-700",
    none:     "bg-gray-200  text-gray-700"
  }.freeze

  def due_pill_class(card)
    DUE_PILL_CLASSES[card.due_status]
  end

  def due_pill_label(card)
    return nil if card.due_date.blank?
    card.due_date.strftime("%b %-d")
  end

  # Format the due date for the <input type="datetime-local"> field.
  # That input requires "YYYY-MM-DDTHH:MM" with no timezone.
  def due_date_for_input(card)
    card.due_date&.strftime("%Y-%m-%dT%H:%M")
  end

  # Cover thumbnail for the board view. resize_to_fill crops to fit the exact
  # box (no letterboxing), which gives the uniform Trello-style strip across
  # the top of every card. Cloudinary serves and caches each variant.
  def card_cover_url(card)
    image = card.cover_image
    return nil unless image
    url_for(image.variant(resize_to_fill: [560, 200]).processed)
  end
end
