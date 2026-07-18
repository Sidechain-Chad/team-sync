module AccountHelper
  # Single source of truth for the four Personal Settings destinations —
  # shared by the sidebar (lg+) and tab row (below lg) so they can't drift.
  def account_nav_links
    [
      { key: :profile,  path: account_profile_path,  icon: "fa-solid fa-user",              label: "Profile" },
      { key: :activity, path: account_activity_path, icon: "fa-solid fa-clock-rotate-left",  label: "Activity" },
      { key: :cards,     path: account_cards_path,    icon: "fa-solid fa-address-card",       label: "Cards" },
      { key: :settings,  path: account_settings_path, icon: "fa-solid fa-gear",               label: "Settings" }
    ]
  end
end
