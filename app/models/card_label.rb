class CardLabel < ApplicationRecord
  belongs_to :card
  belongs_to :label
end
