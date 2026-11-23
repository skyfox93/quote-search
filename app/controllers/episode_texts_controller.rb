class EpisodeTextsController < ApplicationController
  # GET /episode_texts?query=...
  # Renders straight away; the results load into a Turbo Frame from #results,
  # so the page (with a loading state) appears before the search finishes.
  def index
    @query = search_query
  end

  # GET /episode_texts/results?query=...  (the Turbo Frame's src)
  def results
    @query = search_query
    return if @query.blank?

    @search = SemanticSearch.call(@query, use_filters: params[:all] != "1")
    @terms = ScriptText.terms(@search.plan.keywords, @query)
    @indexed_series = SemanticSearch.indexed_series
  rescue OpenaiApi::Error => e
    Rails.logger.error("[semantic search] #{e.message}")
    @error = OpenaiApi.configured? ? "Semantic search is unavailable right now. Please try again." :
                                     "Semantic search needs an OpenAI API key (OPENAI_API_KEY)."
  end

  # GET /episode_texts/:id
  # Optional ?chunk=ID&line=N&lines=N highlights the lines a search result
  # showed, and the link's #match anchor scrolls to them.
  def show
    @episode = EpisodeText.find(params[:id])
    @lines = ScriptText.lines(@episode.text)
    @highlight = highlight_range
  end

  private

  def search_query
    params[:query].to_s.squish.truncate(SearchQueryPlanner::MAX_QUERY_LENGTH, omission: "")
  end

  def highlight_range
    chunk = @episode.episode_chunks.find_by(id: params[:chunk]) if params[:chunk].present?
    return unless chunk

    first = params[:line].to_i.clamp(0, 500)
    count = params[:lines].to_i.clamp(1, 30)
    helpers.chunk_line_range(@episode.text, chunk, first, count)
  end
end
