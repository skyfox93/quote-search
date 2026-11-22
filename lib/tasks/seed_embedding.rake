# Splits episode scripts into chunks and stores an OpenAI embedding for each
# chunk in Postgres (pgvector). Safe to re-run: episodes that already have
# chunks are skipped unless FORCE=1.
#
#   bin/rails seed_embedding              # TNG only (default)
#   SERIES=DS9 bin/rails seed_embedding
#   SERIES=all FORCE=1 bin/rails seed_embedding
desc "Generate pgvector embeddings for episode texts"
task seed_embedding: :environment do
  series = ENV.fetch("SERIES", "TNG")
  force = ENV["FORCE"] == "1"

  scope = series == "all" ? EpisodeText.all : EpisodeText.where(series: series)
  scope = scope.where.not(id: EpisodeChunk.select(:episode_text_id)) unless force

  total = scope.count
  scope.find_each.with_index(1) do |episode, i|
    contents = EpisodeChunk.split(episode.text)
    puts "[#{i}/#{total}] episode #{episode.id} (#{episode.series} #{episode.episode}): #{contents.size} chunks"
    next if contents.empty?

    embeddings = contents.each_slice(100).flat_map { |slice| OpenaiEmbeddings.embed(slice) }
    now = Time.current
    rows = contents.zip(embeddings).each_with_index.map do |(content, embedding), position|
      { episode_text_id: episode.id, position: position, content: content,
        embedding: embedding, created_at: now, updated_at: now }
    end

    EpisodeChunk.transaction do
      episode.episode_chunks.delete_all
      EpisodeChunk.insert_all!(rows)
    end
  end
end
