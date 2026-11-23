require "net/http"
require "json"

# Minimal JSON client for the OpenAI REST API. Reads ENV["OPENAI_API_KEY"].
module OpenaiApi
  BASE_URL = "https://api.openai.com/v1/".freeze

  class Error < StandardError; end

  def self.configured?
    ENV["OPENAI_API_KEY"].present?
  end

  def self.post(path, body, read_timeout: 30)
    uri = URI.join(BASE_URL, path)
    req = Net::HTTP::Post.new(uri)
    req["Authorization"] = "Bearer #{ENV.fetch("OPENAI_API_KEY")}"
    req.content_type = "application/json"
    req.body = body.to_json

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 5, read_timeout: read_timeout) do |http|
      http.request(req)
    end
    raise Error, "OpenAI #{path} failed (#{res.code}): #{res.body.to_s.truncate(500)}" unless res.is_a?(Net::HTTPSuccess)

    JSON.parse(res.body)
  rescue KeyError, JSON::ParserError, Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError => e
    raise Error, "OpenAI #{path} failed: #{e.class}: #{e.message}"
  end
end
