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

ActiveRecord::Schema[8.1].define(version: 2026_11_07_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

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
    t.check_constraint "status::text = ANY (ARRAY['flying'::character varying, 'collected'::character varying, 'lost'::character varying]::text[])", name: "balloons_status_check"
  end

  create_table "favorites", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "balloon_id", null: false
    t.date "collected_on", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["balloon_id"], name: "index_favorites_on_balloon_id", unique: true
    t.index ["user_id", "collected_on"], name: "index_favorites_on_user_id_and_collected_on", unique: true
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

  create_table "pops", primary_key: ["balloon_id", "user_id"], force: :cascade do |t|
    t.bigint "balloon_id", null: false
    t.bigint "user_id", null: false
    t.datetime "popped_at", null: false
    t.index ["user_id"], name: "index_pops_on_user_id"
  end

  create_table "tracks", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "title", null: false
    t.string "artist", null: false
    t.string "mp3_url", null: false
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

  add_foreign_key "auth_tokens", "users"
  add_foreign_key "balloons", "tracks"
  add_foreign_key "balloons", "users"
  add_foreign_key "favorites", "balloons"
  add_foreign_key "favorites", "users"
  add_foreign_key "journeys", "balloons"
  add_foreign_key "plays", "balloons"
  add_foreign_key "plays", "users"
  add_foreign_key "pops", "balloons"
  add_foreign_key "pops", "users"
  add_foreign_key "tracks", "users"
end
