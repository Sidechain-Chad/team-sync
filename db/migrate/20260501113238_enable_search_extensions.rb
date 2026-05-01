class EnableSearchExtensions < ActiveRecord::Migration[7.1]
  # pg_trgm: powers fuzzy/typo-tolerant matching via trigram similarity.
  #   Lets us match "wetlnd" to "wetland".
  #
  # unaccent: strips accents during matching so "Sao Paulo" finds
  #   cards titled "São Paulo". Useful for international names —
  #   crew, locations, talent.
  #
  # Both are bundled with Postgres, no install needed; we just enable them.
  def change
    enable_extension "pg_trgm" unless extension_enabled?("pg_trgm")
    enable_extension "unaccent" unless extension_enabled?("unaccent")
  end
end
