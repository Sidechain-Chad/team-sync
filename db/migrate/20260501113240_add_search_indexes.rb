class AddSearchIndexes < ActiveRecord::Migration[7.1]
  # GIN trigram indexes — these make ILIKE-style and similarity()
  # queries scale. Without them, fuzzy search across 100k cards
  # would do a sequential scan and take seconds; with them it's
  # tens of milliseconds.
  #
  # disable_ddl_transaction! lets us use CONCURRENTLY, which builds
  # the index without blocking writes. Important when this hits
  # production where users are actively editing cards.
  disable_ddl_transaction!

  def up
    unless index_name_exists?(:cards, "index_cards_on_title_trgm")
      add_index :cards, :title,
                using: :gin,
                opclass: :gin_trgm_ops,
                name: "index_cards_on_title_trgm",
                algorithm: :concurrently
    end

    unless index_name_exists?(:cards, "index_cards_on_description_trgm")
      add_index :cards, :description,
                using: :gin,
                opclass: :gin_trgm_ops,
                name: "index_cards_on_description_trgm",
                algorithm: :concurrently
    end

    unless index_name_exists?(:boards, "index_boards_on_name_trgm")
      add_index :boards, :name,
                using: :gin,
                opclass: :gin_trgm_ops,
                name: "index_boards_on_name_trgm",
                algorithm: :concurrently
    end

    unless index_name_exists?(:comments, "index_comments_on_content_trgm")
      add_index :comments, :content,
                using: :gin,
                opclass: :gin_trgm_ops,
                name: "index_comments_on_content_trgm",
                algorithm: :concurrently
    end
  end

  def down
    remove_index :cards,    name: "index_cards_on_title_trgm",       algorithm: :concurrently
    remove_index :cards,    name: "index_cards_on_description_trgm", algorithm: :concurrently
    remove_index :boards,   name: "index_boards_on_name_trgm",       algorithm: :concurrently
    remove_index :comments, name: "index_comments_on_content_trgm",     algorithm: :concurrently
  end
end
