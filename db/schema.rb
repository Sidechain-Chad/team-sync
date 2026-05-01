# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2026_05_01_113240) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_trgm"
  enable_extension "plpgsql"
  enable_extension "unaccent"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "activities", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "card_id", null: false
    t.string "action"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["card_id"], name: "index_activities_on_card_id"
    t.index ["user_id"], name: "index_activities_on_user_id"
  end

  create_table "board_favorites", force: :cascade do |t|
    t.bigint "board_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["board_id"], name: "index_board_favorites_on_board_id"
    t.index ["user_id", "board_id"], name: "index_board_favorites_on_user_id_and_board_id", unique: true
    t.index ["user_id", "created_at"], name: "index_board_favorites_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_board_favorites_on_user_id"
  end

  create_table "board_users", force: :cascade do |t|
    t.bigint "board_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["board_id"], name: "index_board_users_on_board_id"
    t.index ["user_id"], name: "index_board_users_on_user_id"
  end

  create_table "boards", force: :cascade do |t|
    t.string "name"
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_boards_on_name_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["user_id"], name: "index_boards_on_user_id"
  end

  create_table "card_labels", force: :cascade do |t|
    t.bigint "card_id", null: false
    t.bigint "label_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["card_id", "label_id"], name: "index_card_labels_on_card_id_and_label_id", unique: true
    t.index ["card_id"], name: "index_card_labels_on_card_id"
    t.index ["label_id"], name: "index_card_labels_on_label_id"
  end

  create_table "card_members", force: :cascade do |t|
    t.bigint "card_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["card_id"], name: "index_card_members_on_card_id"
    t.index ["user_id"], name: "index_card_members_on_user_id"
  end

  create_table "cards", force: :cascade do |t|
    t.string "title"
    t.text "description"
    t.bigint "list_id", null: false
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "assignee_id"
    t.datetime "due_date"
    t.boolean "completed", default: false, null: false
    t.datetime "archived_at"
    t.index ["assignee_id"], name: "index_cards_on_assignee_id"
    t.index ["description"], name: "index_cards_on_description_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["list_id"], name: "index_cards_on_list_id"
    t.index ["title"], name: "index_cards_on_title_trgm", opclass: :gin_trgm_ops, using: :gin
  end

  create_table "checklist_items", force: :cascade do |t|
    t.bigint "checklist_id", null: false
    t.string "content"
    t.boolean "completed", default: false, null: false
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["checklist_id"], name: "index_checklist_items_on_checklist_id"
  end

  create_table "checklists", force: :cascade do |t|
    t.bigint "card_id", null: false
    t.string "title"
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["card_id"], name: "index_checklists_on_card_id"
  end

  create_table "comments", force: :cascade do |t|
    t.text "content"
    t.bigint "card_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["card_id"], name: "index_comments_on_card_id"
    t.index ["content"], name: "index_comments_on_content_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["user_id"], name: "index_comments_on_user_id"
  end

  create_table "labels", force: :cascade do |t|
    t.bigint "board_id", null: false
    t.string "name"
    t.string "color", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["board_id"], name: "index_labels_on_board_id"
  end

  create_table "lists", force: :cascade do |t|
    t.string "name"
    t.bigint "board_id", null: false
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["board_id"], name: "index_lists_on_board_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "name"
    t.datetime "deactivated_at"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "activities", "cards"
  add_foreign_key "activities", "users"
  add_foreign_key "board_favorites", "boards"
  add_foreign_key "board_favorites", "users"
  add_foreign_key "board_users", "boards"
  add_foreign_key "board_users", "users"
  add_foreign_key "boards", "users"
  add_foreign_key "card_labels", "cards"
  add_foreign_key "card_labels", "labels"
  add_foreign_key "card_members", "cards"
  add_foreign_key "card_members", "users"
  add_foreign_key "cards", "lists"
  add_foreign_key "cards", "users", column: "assignee_id"
  add_foreign_key "checklist_items", "checklists"
  add_foreign_key "checklists", "cards"
  add_foreign_key "comments", "cards"
  add_foreign_key "comments", "users"
  add_foreign_key "labels", "boards"
  add_foreign_key "lists", "boards"
end
