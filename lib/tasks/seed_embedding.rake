# Splits episode scripts into scenes and stores an OpenAI embedding for each
# scene in Postgres (pgvector). Safe to re-run: episodes that already have
# chunks are skipped unless FORCE=1.
#
#   bin/rails seed_embedding              # TNG only (default)
#   SERIES=DS9 bin/rails seed_embedding
#   SERIES=all FORCE=1 bin/rails seed_embedding
#
# It paces itself to stay well under OpenAI's rate limits (TOKENS_PER_MINUTE,
# default 300,000), and waits and retries when it is rate limited anyway.
desc "Generate pgvector embeddings for episode texts"
task seed_embedding: :environment do
  series = ENV.fetch("SERIES", "TNG")
  force = ENV["FORCE"] == "1"
  tokens_per_minute = ENV.fetch("TOKENS_PER_MINUTE", "300000").to_f

  scope = series == "all" ? EpisodeText.all : EpisodeText.where(series: series)
  scope = scope.where.not(id: EpisodeChunk.select(:episode_text_id)) unless force

  # Sends one batch, retrying rate limits (429) and server errors with
  # exponential backoff. Then sleeps long enough that the average rate stays
  # under tokens_per_minute (about 4 characters per token).
  embed = lambda do |texts|
    attempt = 0
    begin
      vectors = OpenaiEmbeddings.embed(texts)
    rescue OpenaiApi::Error => e
      attempt += 1
      retryable = e.message.match?(/\((429|5\d\d)\)|Timeout|EOFError|ECONNRESET/)
      raise unless retryable && attempt <= 8

      wait = [2**attempt, 120].min
      puts "  #{e.message.truncate(120)}; retrying in #{wait}s (attempt #{attempt})"
      sleep wait
      retry
    end
    sleep(texts.sum(&:length) / 4.0 / tokens_per_minute * 60)
    vectors
  end

  total = scope.count
  scope.order(:id).find_each.with_index(1) do |episode, i|
    contents = EpisodeChunk.split(episode.text)
    puts "[#{i}/#{total}] episode #{episode.id} (#{episode.series} #{episode.episode}): #{contents.size} scenes"
    next if contents.empty?

    embeddings = contents.each_slice(100).flat_map { |slice| embed.(slice) }
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

  puts "Done: #{EpisodeChunk.count} scenes across #{EpisodeChunk.distinct.count(:episode_text_id)} episodes."
end
