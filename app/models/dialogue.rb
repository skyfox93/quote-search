class Dialogue < ApplicationRecord
    conn = ActiveRecord::Base.connection
    scope :search, -> (query){ select("dialogues.*, ts_rank_cd(dialogues.searchable, websearch_to_tsquery('simple',
       #{conn.quote(query)})) as rank").where("dialogues.searchable @@ websearch_to_tsquery('simple', ?)", query).order('rank DESC')}
    
end
