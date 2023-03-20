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


file = File.read('./db/all_scripts_raw.json')
data = JSON.parse(file)
data.each do |series, details|
        data[series].each do |episode, char_lines|
            dialogue = []
            EpisodeText.create({episode:episode, text:char_lines, series:series})
            char_lines.split("\n(?=[A-Z,'-]{3,})").each_with_index do |charline, index|
                split_line = charline.split(/([A-Z,'-]{3,}:)/)
                if split_line.length == 1
                  dialogue.push({"index": index, "line": split_line[0], "char": "SCENE", episode: episode, series: series})
                elsif split_line.length >= 3
                  char = split_line[1]
                  line = split_line[2]
                  dialogue.push({"index": index, "line": line.gsub("\n", ' ').strip(), "character": char, episode: episode, series: series})
                end
            end
            Dialogue.insert_all(dialogue)
        end
end

