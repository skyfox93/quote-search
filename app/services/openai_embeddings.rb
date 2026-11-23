# Turns text into vectors with the OpenAI embeddings endpoint.
class OpenaiEmbeddings
  MODEL = "text-embedding-3-small".freeze
  DIMENSIONS = 1536

  # Returns one embedding (Array<Float>) per input string, in order.
  def self.embed(inputs)
    inputs = Array(inputs)
    return [] if inputs.empty?

    data = OpenaiApi.post("embeddings", { model: MODEL, input: inputs }, read_timeout: 60)["data"]
    data.sort_by { |d| d["index"] }.map { |d| d["embedding"] }
  end

  # Like embed, but remembers each text's vector in Rails.cache, and only
  # sends the texts it hasn't seen (all of them in one request).
  def self.embed_cached(inputs, expires_in: 1.week)
    inputs = Array(inputs)
    keys = inputs.to_h { |text| [text, cache_key(text)] }
    found = Rails.cache.read_multi(*keys.values.uniq)
    missing = inputs.uniq.reject { |text| found.key?(keys[text]) }

    if missing.any?
      embed(missing).each_with_index do |vector, i|
        found[keys[missing[i]]] = vector
        Rails.cache.write(keys[missing[i]], vector, expires_in: expires_in)
      end
    end

    inputs.map { |text| found.fetch(keys[text]) }
  end

  def self.cache_key(text)
    "openai/embedding/#{MODEL}/#{Digest::SHA256.hexdigest(text)}"
  end
end
