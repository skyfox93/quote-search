# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: "Star Wars" }, { name: "Lord of the Rings" }])
#   Character.create(name: "Luke", movie: movies.first)
require 'json'

file = File.read('./db/quotes.json')
data = JSON.parse(file)
puts 'open'
puts data.length
puts (data.length/100)
for i in 0..(data.length/100) do
    raw = data[(100*i)..(100*(i+1))]
    batch = raw.collect{|quote| {content: quote["Quote"], author: quote["Author"]}}
    batch.compact!
    puts batch
    if batch.length > 0
        Quote.insert_all(batch)
    end
end


# Episodes and their lines. TranscriptParser splits each raw transcript into
# speeches ("NAME: ..." at the start of a line) and SCENE text (stage
# directions, locations, narration), and CharacterName standardizes speakers.
scripts = JSON.parse(File.read('./db/all_scripts_raw.json'))
scripts.each do |series, episodes|
  episodes.each do |episode, raw|
    parser = TranscriptParser.new(raw)
    next if parser.blocks.empty?

    number = EpisodeText.numbers.dig(series, episode) || {}
    EpisodeText.create!(episode: episode, series: series, text: parser.text,
                        title: EpisodeText.title_from_script(raw),
                        season: number["season"], episode_number: number["number"])
    Dialogue.insert_all!(parser.dialogue_rows(series: series, episode: episode))
  end
end
Dialogue.link_episodes
