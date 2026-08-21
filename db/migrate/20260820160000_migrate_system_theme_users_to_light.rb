class MigrateSystemThemeUsersToLight < ActiveRecord::Migration[7.1]
  # "Match system" is being removed (light/dark only, going forward — see
  # User::THEMES). Existing rows stored as "system" have to land somewhere:
  # "light" is the safe, non-surprising direction, since a user who was on
  # system with a dark OS lands on light rather than being silently switched
  # into dark. Data-only, no column/validation change — that already happened
  # in the User model.
  def up
    execute "UPDATE users SET theme = 'light' WHERE theme = 'system'"
  end

  def down
    # Irreversible by design: which "system" rows to restore can't be
    # recovered once collapsed into "light".
    raise ActiveRecord::IrreversibleMigration
  end
end
