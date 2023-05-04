class Dialogue < ApplicationRecord
    scope :search, -> (query, conn){ select("dialogues.*, ts_rank_cd(dialogues.searchable, websearch_to_tsquery('simple',
       #{conn.quote(query)})) as rank").where("dialogues.searchable @@ websearch_to_tsquery('simple', ?)", query).order('rank DESC')}
    scope :search_english, -> (query, conn){ select("dialogues.*, ts_rank_cd(dialogues.searchable_english, websearch_to_tsquery('english',
        #{conn.quote(query)})) as rank").where("dialogues.searchable_english @@ websearch_to_tsquery('english', ?)", query).order('rank DESC')}
end
