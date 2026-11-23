require "csv"

namespace :characters do
  # Writes every speaker name with its line count, before and after
  # standardizing, to tmp/character_names.csv (or CSV=path).
  desc "List all character names (raw and standardized) with line counts as CSV"
  task list: :environment do
    path = ENV.fetch("CSV", Rails.root.join("tmp/character_names.csv").to_s)
    column = Dialogue.column_names.include?("character_raw") ? "COALESCE(character_raw, character)" : "character"
    raw = Dialogue.group(:series, Arel.sql(column)).count
    CSV.open(path, "w") do |csv|
      csv << %w[series raw_name standardized_name delivery lines]
      raw.sort_by { |(series, name), n| [series, -n, name.to_s] }.each do |(series, name), n|
        std = CharacterName.standardize(name, series: series)
        csv << [series, name, std.name, std.note, n]
      end
    end
    puts "Wrote #{raw.size} series/name pairs to #{path}"
  end

  # Sets dialogues.character to the standardized name and dialogues.delivery
  # to any delivery note, keeping the original in character_raw. Always works
  # from character_raw, so it is safe to re-run after changing CharacterName.
  desc "Standardize dialogue character names (keeps originals in character_raw)"
  task standardize: :environment do
    conn = ActiveRecord::Base.connection
    Dialogue.transaction do
      copied = Dialogue.where(character_raw: nil).update_all("character_raw = character")
      puts "Saved #{copied} original names to character_raw" if copied.positive?

      pairs = Dialogue.distinct.pluck(:series, :character_raw)
      conn.execute("CREATE TEMP TABLE character_map (series text, raw text, name text, delivery text) ON COMMIT DROP")
      pairs.each_slice(1000) do |slice|
        values = slice.map do |series, raw|
          std = CharacterName.standardize(raw, series: series)
          "(#{[series, raw, std.name, std.note].map { conn.quote(_1) }.join(", ")})"
        end
        conn.execute("INSERT INTO character_map VALUES #{values.join(", ")}")
      end

      updated = conn.update(<<~SQL)
        UPDATE dialogues d
        SET character = m.name, delivery = m.delivery
        FROM character_map m
        WHERE d.series IS NOT DISTINCT FROM m.series AND d.character_raw IS NOT DISTINCT FROM m.raw
          AND (d.character IS DISTINCT FROM m.name OR d.delivery IS DISTINCT FROM m.delivery)
      SQL
      before = pairs.map(&:last).uniq.size
      after = Dialogue.distinct.count(:character)
      puts "Updated #{updated} lines. Distinct names: #{before} raw -> #{after} standardized."
    end
  end
end
