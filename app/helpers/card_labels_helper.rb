module CardLabelsHelper
  # Tailwind utility classes for each label color.
  # Returns a hash with :solid (used on pills) and :hover (used in the picker).
  LABEL_COLOR_CLASSES = {
    "green"  => { solid: "bg-green-500  text-white",  hover: "hover:bg-green-600"  },
    "yellow" => { solid: "bg-yellow-400 text-yellow-900", hover: "hover:bg-yellow-500" },
    "orange" => { solid: "bg-orange-500 text-white",  hover: "hover:bg-orange-600" },
    "red"    => { solid: "bg-red-500    text-white",  hover: "hover:bg-red-600"    },
    "purple" => { solid: "bg-purple-500 text-white",  hover: "hover:bg-purple-600" },
    "blue"   => { solid: "bg-blue-500   text-white",  hover: "hover:bg-blue-600"   },
    "sky"    => { solid: "bg-sky-400    text-white",  hover: "hover:bg-sky-500"    },
    "lime"   => { solid: "bg-lime-400   text-lime-900",  hover: "hover:bg-lime-500"   },
    "pink"   => { solid: "bg-pink-400   text-white",  hover: "hover:bg-pink-500"   },
    "black"  => { solid: "bg-gray-800   text-white",  hover: "hover:bg-gray-900"   }
  }.freeze

  def label_solid_class(color)
    LABEL_COLOR_CLASSES.dig(color, :solid) || "bg-gray-300 text-gray-800"
  end

  def label_hover_class(color)
    LABEL_COLOR_CLASSES.dig(color, :hover) || "hover:bg-gray-400"
  end
end
