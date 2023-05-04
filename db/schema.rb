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

ActiveRecord::Schema[7.0].define(version: 2023_05_04_013827) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

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
    t.index ["searchable"], name: "dialogues_search_index", using: :gin
    t.index ["searchable"], name: "index_dialogues_on_searchable", using: :gin
  end

  create_table "episode_texts", force: :cascade do |t|
    t.string "series"
    t.string "episode"
    t.text "text"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "quotes", force: :cascade do |t|
    t.string "content"
    t.string "author"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.virtual "searchable", type: :tsvector, as: "(setweight(to_tsvector('simple'::regconfig, (COALESCE(content, ''::character varying))::text), 'A'::\"char\") || setweight(to_tsvector('simple'::regconfig, (COALESCE(author, ''::character varying))::text), 'B'::\"char\"))", stored: true
    t.index ["searchable"], name: "index_quotes_on_searchable", using: :gin
  end

end
