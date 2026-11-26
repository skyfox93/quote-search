class EpisodeTextsController < ApplicationController
  # GET /episode_texts?query=...
  # Renders straight away; the results load into a Turbo Frame from #results,
  # so the page (with a loading state) appears before the search finishes.
  #
  # Optional ?series=TNG searches only that series.
  def index
    @query = search_query
    @series = series_param
  end

  # GET /episode_texts/results?query=...&series=...  (the Turbo Frame's src)
  # Searches with the query exactly as typed.
  def results
    @query = search_query
    @series = series_param
    return if @query.blank?

    @search = SemanticSearch.call(@query, series: @series)
    @terms = ScriptText.terms(@query)
    @indexed_series = SemanticSearch.indexed_series
  rescue OpenaiApi::Error => e
    Rails.logger.error("[semantic search] #{e.message}")
    @error = OpenaiApi.configured? ? "Semantic search is unavailable right now. Please try again." :
                                     "Semantic search needs an OpenAI API key (OPENAI_API_KEY)."
  end

  # GET /episode_texts/suggestion?query=...&series=...  (a lazy Turbo Frame
  # under the search box)
  # SearchQueryPlanner's tidied version of the query ("in what episode does
  # Geordi become an assassin" -> "Geordi become an assassin", in TNG),
  # offered as a link rather than used, so the search stays exactly what the
  # user typed. Renders nothing when it adds nothing.
  def suggestion
    @query = search_query
    @series = series_param
    return if @query.blank? || !OpenaiApi.configured?

    plan = SearchQueryPlanner.plan(@query)
    new_series = plan.series if plan.series && plan.series != @series
    @suggestion = plan if new_series || !plan.query.casecmp?(@query)
  rescue OpenaiApi::Error => e
    Rails.logger.error("[search suggestion] #{e.message}")
  end

  # GET /episode_texts/:id
  # With ?chunk=ID (a search result's scene), shows only that scene, and
  # &line=N&lines=N highlights the lines the result showed; the link's #match
  # anchor scrolls to them. Without it, shows the whole script.
  def show
    @episode = EpisodeText.find(params[:id])
    @scene = @episode.episode_chunks.find_by(id: params[:chunk]) if params[:chunk].present?
    @lines = ScriptText.lines(@scene ? @scene.content : @episode.text)
    @highlight = scene_highlight if @scene
  end

  private

  def search_query
    params[:query].to_s.squish.truncate(SearchQueryPlanner::MAX_QUERY_LENGTH, omission: "")
  end

  def series_param
    params[:series].presence_in(EpisodeText::SERIES.keys)
  end

  # The lines of the scene that the search result showed.
  def scene_highlight
    first = params[:line].to_i.clamp(0, 500)
    count = params[:lines].to_i.clamp(1, 30)
    first...(first + count)
  end
end
