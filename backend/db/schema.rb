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

ActiveRecord::Schema[8.1].define(version: 2026_11_08_140000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

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

  create_table "auth_tokens", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "token_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["token_digest"], name: "index_auth_tokens_on_token_digest", unique: true
    t.index ["user_id"], name: "index_auth_tokens_on_user_id"
  end

  create_table "balloons", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "track_id", null: false
    t.string "status", default: "flying", null: false
    t.string "origin_label", null: false
    t.float "origin_lat", null: false
    t.float "origin_lng", null: false
    t.float "lat", null: false
    t.float "lng", null: false
    t.float "speed_east", default: 0.0, null: false
    t.float "speed_north", default: 0.0, null: false
    t.datetime "moved_at", null: false
    t.integer "play_count", default: 0, null: false
    t.datetime "launched_at", null: false
    t.datetime "ended_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "last_port"
    t.integer "bound_for"
    t.datetime "boarded_at"
    t.index ["id"], name: "index_balloons_flying", where: "((status)::text = 'flying'::text)"
    t.index ["track_id"], name: "index_balloons_on_track_id"
    t.index ["user_id"], name: "index_balloons_on_user_id"
    t.index ["user_id"], name: "index_balloons_on_user_id_flying", unique: true, where: "((status)::text = 'flying'::text)"
    t.check_constraint "play_count >= 0", name: "balloons_play_count_check"
    t.check_constraint "status::text = ANY (ARRAY['flying'::character varying, 'collected'::character varying, 'lost'::character varying, 'landed'::character varying]::text[])", name: "balloons_status_check"
  end

  create_table "favorites", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "balloon_id", null: false
    t.date "collected_on", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "daily_limit_exempt", default: false, null: false
    t.index ["balloon_id"], name: "index_favorites_on_balloon_id", unique: true
    t.index ["user_id", "collected_on"], name: "index_favorites_on_user_id_and_collected_on", unique: true, where: "(daily_limit_exempt = false)"
  end

  create_table "journeys", force: :cascade do |t|
    t.bigint "balloon_id", null: false
    t.string "end_reason", null: false
    t.string "end_label", null: false
    t.float "end_lat", null: false
    t.float "end_lng", null: false
    t.integer "duration_seconds", null: false
    t.integer "play_count", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["balloon_id"], name: "index_journeys_on_balloon_id", unique: true
    t.check_constraint "duration_seconds >= 0", name: "journeys_duration_seconds_check"
    t.check_constraint "play_count >= 0", name: "journeys_play_count_check"
  end

  create_table "plays", primary_key: ["balloon_id", "user_id"], force: :cascade do |t|
    t.bigint "balloon_id", null: false
    t.bigint "user_id", null: false
    t.datetime "played_at", null: false
    t.index ["user_id"], name: "index_plays_on_user_id"
  end

  create_table "tracks", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "title", null: false
    t.string "artist", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_tracks_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  create_table "wind_grid", primary_key: ["lat", "lng", "valid_time"], force: :cascade do |t|
    t.float "lat", null: false
    t.float "lng", null: false
    t.datetime "valid_time", null: false
    t.float "speed_east", null: false
    t.float "speed_north", null: false
    t.datetime "fetched_at", null: false
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "auth_tokens", "users"
  add_foreign_key "balloons", "tracks"
  add_foreign_key "balloons", "users"
  add_foreign_key "favorites", "balloons"
  add_foreign_key "favorites", "users"
  add_foreign_key "journeys", "balloons"
  add_foreign_key "plays", "balloons"
  add_foreign_key "plays", "users"
  add_foreign_key "tracks", "users"
end
