require "json"
require "net/http"

namespace :episodes do
  SCRIPTS_FILE = "db/all_scripts_raw.json"

  # TVMaze show ids (https://www.tvmaze.com/api)
  TVMAZE_SHOWS = { "TOS" => 490, "TAS" => 3513, "TNG" => 491, "DS9" => 493, "VOY" => 492, "ENT" => 714 }.freeze

  # Transcript titles that can't be matched by normalising spelling.
  TITLE_OVERRIDES = { "DS9" => { "Till Death Us Do Part" => "'Til Death Do Us Part" } }.freeze

  normalize = ->(name) { EpisodeText.normalize_title(name) } # resolved lazily, after :environment

  desc "Look up season/episode numbers on TVMaze and write db/episode_numbers.json"
  task fetch_numbers: :environment do
    scripts = JSON.parse(File.read(Rails.root.join(SCRIPTS_FILE)))
    result = {}
    problems = []

    TVMAZE_SHOWS.each do |series, show_id|
      uri = URI("https://api.tvmaze.com/shows/#{show_id}/episodes?specials=1")
      res = Net::HTTP.get_response(uri)
      raise "TVMaze request failed for #{series} (#{res.code})" unless res.is_a?(Net::HTTPSuccess)

      ref = JSON.parse(res.body).select { |e| e["type"] == "regular" || e["type"] == "significant_special" }
      by_name = ref.group_by { |e| normalize.(e["name"]) }
      # Arc episodes are listed as e.g. "Cold Station 12 (2)", so also index names without the part number.
      by_base = ref.group_by { |e| normalize.(e["name"]).sub(/\s+part \d+\z/, "") }
      used = {}

      result[series] = scripts.fetch(series).to_h do |key, raw|
        title = EpisodeText.title_from_script(raw)
        lookup = TITLE_OVERRIDES.dig(series, title) || title
        # Two-part episodes listed twice (e.g. "Encounter at Farpoint" 1x01 and 1x02) use the first part.
        candidates = by_name[normalize.(lookup)] || by_base[normalize.(lookup)]
        match = candidates&.min_by { |e| [e["season"], e["number"] || 0] }

        if match.nil?
          problems << "#{series} #{key}: no TVMaze match for #{title.inspect}"
        elsif used[match["id"]]
          problems << "#{series} #{key}: #{title.inspect} matched the same TVMaze episode as #{used[match["id"]]}"
        else
          used[match["id"]] = key
        end

        [key, match && { "season" => match["season"], "number" => match["number"], "tvmaze_name" => match["name"] }]
      end
    end

    if problems.any?
      abort "Not written. Fix these first:\n  #{problems.join("\n  ")}"
    end

    File.write(EpisodeText::NUMBERS_FILE, JSON.pretty_generate(result) + "\n")
    puts "Wrote #{result.values.sum(&:size)} episodes to #{EpisodeText::NUMBERS_FILE}"
  end

  # Fills in title, season and episode number for rows seeded before those
  # columns existed. Safe to re-run.
  desc "Set episode titles and season/episode numbers"
  task backfill: :environment do
    scripts = JSON.parse(File.read(Rails.root.join(SCRIPTS_FILE)))
    abort "Missing #{EpisodeText::NUMBERS_FILE}; run bin/rails episodes:fetch_numbers" if EpisodeText.numbers.empty?

    updated = 0
    scripts.each do |series, episodes|
      episodes.each do |episode, raw|
        number = EpisodeText.numbers.dig(series, episode) || {}
        updated += EpisodeText.where(series: series, episode: episode).update_all(
          title: EpisodeText.title_from_script(raw), season: number["season"], episode_number: number["number"]
        )
      end
    end

    puts "Updated #{updated} episodes."
    puts "#{EpisodeText.where(title: nil).count} without a title, #{EpisodeText.where(season: nil).count} without a season."
  end
end
