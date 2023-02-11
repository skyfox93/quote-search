# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: "Star Wars" }, { name: "Lord of the Rings" }])
#   Character.create(name: "Luke", movie: movies.first)
require 'json'

# file = File.read('./db/quotes.json')
# data = JSON.parse(file)
# puts 'open'
# puts data.length
# puts (data.length/100)
# for i in 0..(data.length/100) do
#     raw = data[(100*i)..(100*(i+1))]
#     batch = raw.collect{|quote| {content: quote["Quote"], author: quote["Author"]}}
#     batch.compact!
#     puts batch
#     if batch.length > 0
#         Quote.insert_all(batch)
#     end
# end

file = File.read('./db/all_series_lines.json')
data = JSON.parse(file)
data.each do |series, details|
        data[series].each do |episode, char_lines|
            batch =[]
            char_lines.each do |character, lines|
                lines.each do | line|
                    batch.append({character: character, line: line, episode: episode, series: series})
                end
            end
            Dialogue.insert_all(batch)
        end
end
# file = File.read('./db/all_scripts_raw.json')
# data = JSON.parse(file)
# data.each do |series, details|
#         data[series].each do |episode, char_lines|
#             EpisodeText.create({episode:episode, text:char_lines, series:series})
#         end
# end

