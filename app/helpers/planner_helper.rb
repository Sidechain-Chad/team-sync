module PlannerHelper
  # Colour the planner chip by the card's first label, falling back to a
  # neutral gray if the card has no labels. Keeps the calendar visually
  # parseable at a glance — same colour-language as the cards on the board.
  def planner_chip_classes(card)
    label = card.labels.first
    return "bg-gray-100 text-gray-700 border-l-4 border-gray-300" unless label

    # Reuse the label colour helper your existing label_pills view uses.
    # Mapping is the same set of colours your labels can be.
    case label.color
    when "red"     then "bg-red-50 text-red-800 border-l-4 border-red-500"
    when "orange"  then "bg-orange-50 text-orange-800 border-l-4 border-orange-500"
    when "yellow"  then "bg-yellow-50 text-yellow-800 border-l-4 border-yellow-500"
    when "green"   then "bg-green-50 text-green-800 border-l-4 border-green-500"
    when "lime"    then "bg-lime-50 text-lime-800 border-l-4 border-lime-500"
    when "sky"     then "bg-sky-50 text-sky-800 border-l-4 border-sky-500"
    when "blue"    then "bg-blue-50 text-blue-800 border-l-4 border-blue-500"
    when "purple"  then "bg-purple-50 text-purple-800 border-l-4 border-purple-500"
    when "pink"    then "bg-pink-50 text-pink-800 border-l-4 border-pink-500"
    when "black"   then "bg-gray-100 text-gray-900 border-l-4 border-gray-900"
    else                "bg-gray-100 text-gray-700 border-l-4 border-gray-400"
    end
  end
end
