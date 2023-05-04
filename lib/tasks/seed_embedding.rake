require 'net/http'

task :seed_embedding => :environment do
    dialogue = EpisodeText.where(series: "TNG").find_in_batches(batch_size: 5) do |batch|
        documents_batch = batch.collect{|line|
            puts "processing episode #{line.id}"
            { text: line.text,
                metadata: {
                    source_id: line.id,
                    author: line.series
                }
            }
        }
        uri = URI("http://0.0.0.0")
        hostname = uri.hostname # => "example.com"
        uri.path = '/upsert'
        req = Net::HTTP::Post.new(uri) # => #<Net::HTTP::Post POST>
        req["Authorization"] = ENV["DOCUMENT_RETRIEVAL_TOKEN"]
        req.body = {
            documents: documents_batch
        }.to_json
        req.content_type = 'application/json'
        res = Net::HTTP.start(hostname, 8000) do |http|
            response = http.request(req)
            puts response.read_body
        sleep(5)
        end
    end
end
