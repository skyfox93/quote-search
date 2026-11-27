require "json"
require "net/http"

# Episode summaries from TVMaze (CC BY-SA 4.0; credited in the site footer),
# used by scene search to find episodes by their plot. Three steps, each
# safe to re-run:
#
#   bin/rails episodes:fetch_summaries   # TVMaze -> db/episode_summaries.json (committed)
#   bin/rails episodes:load_summaries    # the JSON file -> episode_texts.summary
#   bin/rails episodes:embed_summaries   # embeds new or changed summaries (FORCE=1: all)
namespace :episodes do
  desc "Download episode summaries from TVMaze into db/episode_summaries.json"
  task fetch_summaries: :environment do
    abort "Missing #{EpisodeText::NUMBERS_FILE}; run bin/rails episodes:fetch_numbers" if EpisodeText.numbers.empty?

    plain = ->(html) { html.to_s.gsub(/<[^>]+>/, " ").then { CGI.unescapeHTML(_1) }.squish }
    result = {}
    missing = []

    TVMAZE_SHOWS.each do |series, show_id|
      res = Net::HTTP.get_response(URI("https://api.tvmaze.com/shows/#{show_id}/episodes?specials=1"))
      raise "TVMaze request failed for #{series} (#{res.code})" unless res.is_a?(Net::HTTPSuccess)

      ref = JSON.parse(res.body)
      # Matched the same way as fetch_numbers did: by TVMaze's name and season.
      result[series] = EpisodeText.numbers.fetch(series, {}).to_h do |key, number|
        match = number && ref.find { _1["name"] == number["tvmaze_name"] && _1["season"] == number["season"] }
        summary = plain.(match&.dig("summary")).presence
        missing << "#{series} #{key}" unless summary
        [key, summary]
      end
      sleep 1 # TVMaze allows 20 calls per 10 seconds
    end

    File.write(EpisodeText::SUMMARIES_FILE, JSON.pretty_generate(result) + "\n")
    puts "Wrote #{result.values.sum { _1.values.compact.size }} summaries to #{EpisodeText::SUMMARIES_FILE}"
    puts "No summary for: #{missing.join(', ')}" if missing.any?
  end

  desc "Copy db/episode_summaries.json into episode_texts.summary"
  task load_summaries: :environment do
    summaries = JSON.parse(EpisodeText::SUMMARIES_FILE.read)
    changed = 0
    EpisodeText.without_text.find_each do |episode|
      summary = summaries.dig(episode.series, episode.episode)
      next if episode.summary == summary

      # A changed summary needs a new embedding.
      changed += EpisodeText.where(id: episode.id).update_all(summary: summary, summary_embedding: nil)
    end
    puts "Updated #{changed} summaries; #{EpisodeText.where(summary: nil).count} episodes have none."
  end

  desc "Embed episode summaries for search (only new or changed ones unless FORCE=1)"
  task embed_summaries: :environment do
    scope = EpisodeText.where.not(summary: nil)
    scope = scope.where(summary_embedding: nil) unless ENV["FORCE"] == "1"
    episodes = scope.select(:id, :title, :summary).order(:id).to_a

    episodes.each_slice(100).with_index do |batch, i|
      attempt = 0
      begin
        vectors = OpenaiEmbeddings.embed(batch.map(&:summary_for_embedding))
      rescue OpenaiApi::Error => e
        attempt += 1
        raise unless e.message.match?(/\((429|5\d\d)\)|Timeout|EOFError|ECONNRESET/) && attempt <= 5

        puts "  #{e.message.truncate(120)}; retrying in #{2**attempt}s"
        sleep 2**attempt
        retry
      end
      EpisodeText.transaction do
        batch.zip(vectors).each do |episode, vector|
          EpisodeText.where(id: episode.id).update_all(["summary_embedding = ?::vector", "[#{vector.join(',')}]"])
        end
      end
      puts "[#{[(i + 1) * 100, episodes.size].min}/#{episodes.size}] embedded"
    end
    puts "Done: #{EpisodeText.where.not(summary_embedding: nil).count} episodes have a summary embedding."
  end
end
