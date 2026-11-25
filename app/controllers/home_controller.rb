# The landing page: a write-up of three levels of search automation, each
# with a snapshot of a real example and a search box to try it live.
class HomeController < ApplicationController
  def index
    @stats = Rails.cache.fetch("home/stats/v2", expires_in: 1.hour) do
      { lines: Dialogue.spoken.count, speakers: Dialogue.spoken.distinct.count(:character),
        episodes: EpisodeText.count, chunks: EpisodeChunk.count }
    end
    @indexed_series = SemanticSearch.indexed_series.map { EpisodeText::SERIES[_1] || _1 }
  end
end
