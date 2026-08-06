class AddThemeToUsers < ActiveRecord::Migration[7.1]
  # Appearance preference, stored server-side so it follows the user across
  # devices — same reasoning as notification_preferences, and the reason the
  # layout can stamp the right theme into the first byte instead of letting JS
  # discover it after paint.
  #
  # Default "light", NOT "system": nobody's appearance changes because they
  # upgraded. Opting into "system" is a choice.
  #
  # null: false + a default means every existing row is backfilled to "light" by
  # the DDL itself, so User#theme is never nil and the layout never has to
  # decide what a nil theme means.
  def change
    add_column :users, :theme, :string, default: "light", null: false
  end
end
