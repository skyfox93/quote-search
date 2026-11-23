# The landing page: three levels of search automation, each with a live
# example. Examples load lazily (Turbo Frames) and reuse the services'
# caches, so the AI ones only cost an API call the first time.
class HomeController < ApplicationController
  EXAMPLES = {
    "keyword" => "assimilating",
    "rag" => "Data tries to learn how to be funny",
    "agent" => "How many times does Picard say \"make it so\", and in which season does he say it most?"
  }.freeze

  def index
    @stats = Rails.cache.fetch("home/stats", expires_in: 1.hour) do
      { lines: Dialogue.count, episodes: EpisodeText.count, chunks: EpisodeChunk.count }
    end
  end

  # GET /examples/:level  (a Turbo Frame)
  def example
    @level = params[:level]
    @query = EXAMPLES.fetch(@level)
    send(:"#{@level}_example")
    render "home/examples/#{@level}"
  rescue OpenaiApi::Error => e
    Rails.logger.error("[landing example] #{e.message}")
    @error = "This example needs the OpenAI API, which isn't available right now."
    render "home/examples/#{@level}"
  end

  private

  def keyword_example
    @keyword = Rails.cache.fetch("home/keyword_example/v3/#{@query}", expires_in: 1.hour) do
      conn = ActiveRecord::Base.connection
      headline = Dialogue.sanitize_sql_array([
        %(ts_headline('english', line, websearch_to_tsquery('english', ?), 'StartSel=⟦, StopSel=⟧, MaxWords=22, MinWords=8, MaxFragments=2, FragmentDelimiter=" … "') AS headline), @query
      ])
      rows = Dialogue.search_english(@query, conn).select(headline).limit(4).to_a
      {
        stem: conn.select_value(Dialogue.sanitize_sql_array(["SELECT websearch_to_tsquery('english', ?)::text", @query])).to_s.delete("'"),
        exact_count: Dialogue.spoken.where("searchable @@ websearch_to_tsquery('simple', ?)", @query).count,
        dictionary_count: Dialogue.spoken.where("searchable_english @@ websearch_to_tsquery('english', ?)", @query).count,
        rows: rows.map { |d| { id: d.id, headline: d.headline, character: d.character, series: d.series, episode: d.episode } },
        titles: EpisodeText.titles_for(rows)
      }
    end
  end

  def rag_example
    raise OpenaiApi::Error, "no API key" unless OpenaiApi.configured?

    @search = SemanticSearch.call(@query)
    @answer = SearchSummarizer.new(@query, @search.hits).stream { nil } if @search.hits.any?
  end

  def agent_example
    raise OpenaiApi::Error, "no API key" unless OpenaiApi.configured?

    @events = SearchAgent.new(@query).run
  end
end
