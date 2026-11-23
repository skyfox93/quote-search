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
end
