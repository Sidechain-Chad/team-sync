Rails.application.routes.draw do
  # 1. Standard Devise routes for Users
  devise_for :users

  # 2. Root path (Home page)
  root 'boards#index'
  get "planner"        => "planner#index",  as: :planner
  get "planner/panel"  => "planner#panel",  as: :planner_panel
  get "switch_boards"  => "boards#switcher", as: :switch_boards
  get "search"         => "search#index",   as: :search

  # 3. Health check (Standard Rails 7.1+)
  get "up" => "rails/health#show", as: :rails_health_check

  # --- APP RESOURCES ---

  resources :boards do
    resources :lists, only: [:create, :update, :destroy]
    resources :board_users, only: [:create, :destroy]
    resources :labels, only: [:new, :create, :edit, :update, :destroy]

    member do
      get :archive
      patch :toggle_favorite
    end
  end

  # Cancel routes for the inline label edit/create forms.
  get "cards/:card_id/labels/:label_id/cancel_edit", to: "labels#cancel_edit", as: :label_row_cancel
  get "cards/:card_id/labels/cancel_new",            to: "labels#cancel_new",  as: :new_label_cancel

  # Lists
  resources :lists do
    member do
      patch :move
    end
    resources :cards, only: [:new, :create]
  end

  # Cards (Top level access)
  resources :cards, only: [:edit, :update, :destroy, :show] do
    resources :members, only: [:create, :destroy], controller: 'card_members', param: :user_id
    resources :comments, only: [:create, :destroy]
    resources :labels, only: [:create, :destroy], controller: 'card_labels', param: :label_id
    
    resources :checklists, only: [:create, :update, :destroy] do
      resources :checklist_items, only: [:create, :update, :destroy]
    end
    resources :attachments, only: [:create, :destroy]

    member do
      patch :move
      get   :edit_description
      patch :update_description
      patch :archive
      patch :unarchive
      patch :toggle_complete
    end
  end
end
