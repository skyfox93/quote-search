require "net/http"
require "json"

# Minimal client for the OpenAI embeddings endpoint.
# Reads the API key from ENV["OPENAI_API_KEY"].
class OpenaiEmbeddings
  MODEL = "text-embedding-3-small".freeze
  DIMENSIONS = 1536
  ENDPOINT = URI("https://api.openai.com/v1/embeddings")

  class Error < StandardError; end

  # Returns one embedding (Array<Float>) per input string, in order.
  def self.embed(inputs)
    inputs = Array(inputs)
    return [] if inputs.empty?

    req = Net::HTTP::Post.new(ENDPOINT)
    req["Authorization"] = "Bearer #{ENV.fetch("OPENAI_API_KEY")}"
    req.content_type = "application/json"
    req.body = { model: MODEL, input: inputs }.to_json

    res = Net::HTTP.start(ENDPOINT.hostname, ENDPOINT.port, use_ssl: true, read_timeout: 60) do |http|
      http.request(req)
    end
    raise Error, "OpenAI embeddings request failed (#{res.code}): #{res.body}" unless res.is_a?(Net::HTTPSuccess)

    JSON.parse(res.body)["data"].sort_by { |d| d["index"] }.map { |d| d["embedding"] }
  end
end
