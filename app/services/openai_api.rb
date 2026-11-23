require "net/http"
require "json"

# Minimal JSON client for the OpenAI REST API. Reads ENV["OPENAI_API_KEY"].
#
# Each thread keeps one HTTPS connection open and reuses it, so only the first
# request pays for the TCP + TLS handshake (a search makes 2-3 requests).
module OpenaiApi
  HOST = "api.openai.com".freeze
  BASE_PATH = "/v1/".freeze
  KEEP_ALIVE = 30 # seconds an idle connection is kept for reuse

  class Error < StandardError; end

  NETWORK_ERRORS = [
    Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError,
    OpenSSL::SSL::SSLError, IOError, EOFError, Net::HTTPBadResponse
  ].freeze

  def self.configured?
    ENV["OPENAI_API_KEY"].present?
  end

  def self.post(path, body, read_timeout: 30)
    req = Net::HTTP::Post.new(BASE_PATH + path)
    req["Authorization"] = "Bearer #{ENV.fetch("OPENAI_API_KEY")}"
    req.content_type = "application/json"
    req.body = body.to_json

    res = with_connection(read_timeout) { |http| http.request(req) }
    raise Error, "OpenAI #{path} failed (#{res.code}): #{res.body.to_s.truncate(500)}" unless res.is_a?(Net::HTTPSuccess)

    JSON.parse(res.body)
  rescue KeyError, JSON::ParserError, *NETWORK_ERRORS => e
    raise Error, "OpenAI #{path} failed: #{e.class}: #{e.message}"
  end

  # Chat completion constrained to a strict JSON schema. Returns the parsed
  # object. The result is still untrusted model output: validate it.
  def self.chat_json(model:, messages:, schema:, name:, reasoning: nil, read_timeout: 30)
    body = {
      model: model,
      messages: messages,
      response_format: { type: "json_schema", json_schema: { name: name, strict: true, schema: schema } }
    }
    body[:reasoning_effort] = reasoning if reasoning.present?
    JSON.parse(post("chat/completions", body, read_timeout: read_timeout).dig("choices", 0, "message", "content").to_s)
  rescue JSON::ParserError => e
    raise Error, "OpenAI returned invalid JSON: #{e.message}"
  end

  # Streams a plain-text chat completion, yielding each piece of text as it
  # arrives. Returns the full text.
  #
  # If the block raises IOError (e.g. the browser went away mid-stream), the
  # rest of the completion is still read, so the full text can be cached and
  # the connection stays reusable, but nothing more is yielded.
  def self.stream_chat(model:, messages:, reasoning: nil, read_timeout: 30)
    body = { model: model, messages: messages, stream: true }
    body[:reasoning_effort] = reasoning if reasoning.present?

    req = Net::HTTP::Post.new(BASE_PATH + "chat/completions")
    req["Authorization"] = "Bearer #{ENV.fetch("OPENAI_API_KEY")}"
    req.content_type = "application/json"
    req.body = body.to_json

    text = +""
    listening = true
    with_connection(read_timeout) do |http|
      http.request(req) do |res|
        unless res.is_a?(Net::HTTPSuccess)
          raise Error, "OpenAI chat/completions failed (#{res.code}): #{res.read_body.to_s.truncate(500)}"
        end

        each_sse_data(res) do |data|
          delta = JSON.parse(data).dig("choices", 0, "delta", "content")
          next if delta.blank?

          text << delta
          begin
            yield delta if listening
          rescue IOError
            listening = false
          end
        end
      end
    end
    text
  rescue KeyError, JSON::ParserError, *NETWORK_ERRORS => e
    raise Error, "OpenAI chat/completions stream failed: #{e.class}: #{e.message}"
  end

  # Server-sent events: yields the payload of each "data: ..." line. Reads the
  # body to the end (never returns early), so a kept-alive connection is left
  # clean for the next request.
  def self.each_sse_data(res)
    buffer = +""
    res.read_body do |chunk|
      buffer << chunk
      while (newline = buffer.index("\n"))
        line = buffer.slice!(0..newline).strip
        next unless line.start_with?("data:")

        data = line.delete_prefix("data:").strip
        yield data unless data == "[DONE]"
      end
    end
  end

  # Yields a started connection, reusing this thread's idle one when possible.
  # A reused connection may have been closed by the server; that only shows up
  # as an error on the next request, so retry once on a fresh connection.
  def self.with_connection(read_timeout)
    retried = false
    begin
      reused = (http = Thread.current[:openai_http])&.started?
      http = Thread.current[:openai_http] = start_connection unless reused
      http.read_timeout = read_timeout
      yield http
    rescue IOError, EOFError, Errno::ECONNRESET, Errno::EPIPE, OpenSSL::SSL::SSLError
      close_connection
      raise if retried || !reused

      retried = true
      retry
    rescue Exception # rubocop:disable Lint/RescueException -- never reuse a connection in an unknown state
      close_connection
      raise
    end
  end

  def self.start_connection
    Net::HTTP.new(HOST, 443).tap do |http|
      http.use_ssl = true
      http.open_timeout = 5
      http.keep_alive_timeout = KEEP_ALIVE
      http.start
    end
  end

  def self.close_connection
    Thread.current[:openai_http]&.finish if Thread.current[:openai_http]&.started?
  rescue IOError
    nil
  ensure
    Thread.current[:openai_http] = nil
  end

  private_class_method :with_connection, :start_connection, :close_connection, :each_sse_data
end
