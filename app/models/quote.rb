class Quote < ApplicationRecord
    include PgSearch::Model
    conn = ActiveRecord::Base.connection
     scope :search, -> (query){ select("quotes.*, ts_rank_cd(quotes.searchable, websearch_to_tsquery('simple',
        #{conn.quote(query)})) as rank").where("quotes.searchable @@ websearch_to_tsquery('simple', ?)", query).order('rank DESC')}
     
end


