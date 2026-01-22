Rails.application.routes.draw do
  # 1. Standard Devise routes for Users
  devise_for :users

  # 2. Root path (Home page)
  root 'boards#index'

  # 3. Health check (Standard Rails 7.1+)
  get "up" => "rails/health#show", as: :rails_health_check

  # --- APP RESOURCES ---

  # Change this:
  # resources :boards, only: [:show, :index]

  # To this (Allow all actions so we can create/edit/destroy):
  resources :boards do
    resources :lists, only: [:create, :update, :destroy]
    resources :board_users, only: [:create, :destroy]
  end

  # Lists
  resources :lists do
    member do
      patch :move # For dragging lists around
    end
    # Nested Cards: POST /lists/:list_id/cards (Creating a card in a specific list)
    resources :cards, only: [:new, :create]
  end

  # Cards (Top level access)
  # :show is crucial for Turbo to "cancel" edits
  resources :cards, only: [:edit, :update, :destroy, :show] do
    resources :members, only: [:create, :destroy], controller: 'card_members', param: :user_id
    member do
      patch :move # For dragging cards around
      get :edit_description # NEW
    end
  end
end
