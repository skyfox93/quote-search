class Dialogue < ApplicationRecord
    belongs_to :episode_text, foreign_key: :episode_id, optional: true

    # Sets each line's episode_id and season_id from its episode (matched on
    # series and episode). Bulk inserts skip them, so call this after one.
    def self.link_episodes
      connection.update(<<~SQL)
        UPDATE dialogues d SET episode_id = e.id, season_id = e.season_id
        FROM episode_texts e
        WHERE e.series = d.series AND e.episode = d.episode
          AND (d.episode_id IS DISTINCT FROM e.id OR d.season_id IS DISTINCT FROM e.season_id)
      SQL
    end

    # Stage directions, locations and narration are stored with character "SCENE".
    scope :spoken, -> { where.not(character: TranscriptParser::SCENE) }

    scope :search, -> (query, conn){ select("dialogues.*, ts_rank_cd(dialogues.searchable, websearch_to_tsquery('simple',
       #{conn.quote(query)})) as rank").spoken.where("dialogues.searchable @@ websearch_to_tsquery('simple', ?)", query).order('rank DESC')}
    scope :search_english, -> (query, conn){ select("dialogues.*, ts_rank_cd(dialogues.searchable_english, websearch_to_tsquery('english',
        #{conn.quote(query)})) as rank").spoken.where("dialogues.searchable_english @@ websearch_to_tsquery('english', ?)", query).order('rank DESC')}
end
