namespace :dialogues do
  # Re-parses every line from db/all_scripts_raw.json with TranscriptParser
  # and replaces the dialogues table. Episodes (and their embeddings) are left
  # alone. Dialogue ids change.
  desc "Rebuild dialogues from db/all_scripts_raw.json (replaces all dialogue rows)"
  task rebuild: :environment do
    scripts = JSON.parse(File.read(Rails.root.join("db/all_scripts_raw.json")))
    rows = scripts.flat_map do |series, episodes|
      episodes.flat_map { |episode, raw| TranscriptParser.new(raw).dialogue_rows(series: series, episode: episode) }
    end

    before = Dialogue.count
    Dialogue.transaction do
      Dialogue.delete_all
      rows.each_slice(5_000) { |slice| Dialogue.insert_all!(slice) }
    end
    Rails.cache.clear

    spoken = Dialogue.spoken
    puts "Replaced #{before} rows with #{Dialogue.count}: #{spoken.count} spoken lines by " \
         "#{spoken.distinct.count(:character)} characters, #{Dialogue.where(character: TranscriptParser::SCENE).count} SCENE rows."
  end
end
