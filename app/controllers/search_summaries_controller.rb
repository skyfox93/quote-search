# GET /search/summary?query=...&series=...
# Streams the AI summary of a search as plain text while the model writes it.
# The results page fetches this once its results have loaded (by then the
# query's embedding is cached, so the search here is fast).
class SearchSummariesController < ApplicationController
  include ActionController::Live

  def show
    query = params[:query].to_s.squish.truncate(SearchQueryPlanner::MAX_QUERY_LENGTH, omission: "")
    return head(:bad_request) if query.blank?
    return head(:service_unavailable) unless OpenaiApi.configured?

    search = SemanticSearch.call(query, series: params[:series].presence_in(EpisodeText::SERIES.keys))
    return head(:no_content) if search.hits.empty?

    response.headers["Content-Type"] = "text/plain; charset=utf-8"
    response.headers["Cache-Control"] = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"           # don't let a proxy buffer the stream
    response.headers["Last-Modified"] = Time.now.httpdate  # stops Rack::ETag buffering it to hash the body

    SearchSummarizer.new(query, search.hits).stream { |piece| response.stream.write(piece) }
  rescue OpenaiApi::Error => e
    Rails.logger.error("[search summary] #{e.message}")
    head(:service_unavailable) unless response.committed?
  ensure
    response.stream.close
  end
end
