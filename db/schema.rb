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

ActiveRecord::Schema[8.1].define(version: 2026_11_27_000000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "vector"

  create_table "dialogues", force: :cascade do |t|
    t.string "line"
    t.string "episode"
    t.string "series"
    t.string "character"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "index"
    t.virtual "searchable", type: :tsvector, as: "(setweight(to_tsvector('simple'::regconfig, (COALESCE(line, ''::character varying))::text), 'B'::\"char\") || setweight(to_tsvector('simple'::regconfig, (COALESCE(\"character\", ''::character varying))::text), 'A'::\"char\"))", stored: true
    t.virtual "searchable_english", type: :tsvector, as: "(setweight(to_tsvector('english'::regconfig, (COALESCE(line, ''::character varying))::text), 'A'::\"char\") || setweight(to_tsvector('english'::regconfig, (COALESCE(\"character\", ''::character varying))::text), 'B'::\"char\"))", stored: true
    t.string "character_raw"
    t.string "delivery"
    t.index ["searchable"], name: "dialogues_search_index", using: :gin
    t.index ["searchable"], name: "index_dialogues_on_searchable", using: :gin
    t.index ["series", "character"], name: "index_dialogues_on_series_and_character"
  end

  create_table "episode_chunks", force: :cascade do |t|
    t.bigint "episode_text_id", null: false
    t.integer "position", null: false
    t.text "content", null: false
    t.vector "embedding", limit: 1536
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["embedding"], name: "index_episode_chunks_on_embedding", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["episode_text_id", "position"], name: "index_episode_chunks_on_episode_text_id_and_position", unique: true
    t.index ["episode_text_id"], name: "index_episode_chunks_on_episode_text_id"
  end

  create_table "episode_texts", force: :cascade do |t|
    t.string "series"
    t.string "episode"
    t.text "text"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "title"
    t.text "summary"
    t.integer "season"
    t.integer "episode_number"
    t.vector "summary_embedding", limit: 1536
    t.index ["series", "episode"], name: "index_episode_texts_on_series_and_episode"
  end

  create_table "quotes", force: :cascade do |t|
    t.string "content"
    t.string "author"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.virtual "searchable", type: :tsvector, as: "(setweight(to_tsvector('simple'::regconfig, (COALESCE(content, ''::character varying))::text), 'A'::\"char\") || setweight(to_tsvector('simple'::regconfig, (COALESCE(author, ''::character varying))::text), 'B'::\"char\"))", stored: true
    t.index ["searchable"], name: "index_quotes_on_searchable", using: :gin
  end

  add_foreign_key "episode_chunks", "episode_texts"
end
