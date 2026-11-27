# Measures scene search on descriptions whose episode is known: for each,
# where the right episode lands in SemanticSearch's results (top
# SemanticSearch::MAX_EPISODES). Uses the real search, so it needs an OpenAI
# key and the embeddings; it only reads the database.
#
#   bin/rails search:eval
namespace :search do
  # Description => [series, title prefix] of the episodes that count as right.
  EVAL_CASES = {
    "Picard lives a whole other life on another planet" => [%w[TNG The\ Inner\ Light]],
    "Picard is captured and turned into a Borg" => [%w[TNG The\ Best\ of\ Both\ Worlds]],
    "A Cardassian tortures Picard and insists he see five lights" => [%w[TNG Chain\ of\ Command]],
    "Data builds an android daughter" => [%w[TNG The\ Offspring]],
    "A trial decides whether Data is a person or Starfleet property" => [%w[TNG The\ Measure\ Of\ A\ Man]],
    "The Enterprise is stuck in a time loop and keeps getting destroyed" => [%w[TNG Cause\ and\ Effect]],
    "Worf keeps shifting between parallel realities" => [%w[TNG Parallels]],
    "Barclay becomes a genius after an alien probe zaps him" => [%w[TNG The\ Nth\ Degree]],
    "A transporter accident creates a second Riker" => [%w[TNG Second\ Chances]],
    "Kirk fights a lizard alien on a desert planet" => [%w[TOS Arena]],
    "Spock must go home to Vulcan to mate or he will die" => [%w[TOS Amok\ Time]],
    "Small furry creatures multiply and overrun the station" =>
      [%w[TOS The\ Trouble\ With\ Tribbles], %w[DS9 Trials\ and\ Tribble], %w[TAS More\ Tribbles]],
    "Sisko lives as a science fiction writer in 1950s New York" => [%w[DS9 Far\ Beyond\ The\ Stars]],
    "Sisko helps fake evidence to bring the Romulans into the war" => [%w[DS9 In\ The\ Pale\ Moonlight]],
    "Jake spends his life trying to rescue his father lost in time" => [%w[DS9 The\ Visitor]],
    "Kira questions a Cardassian who claims to be a war criminal" => [%w[DS9 Duet]],
    "Janeway and Chakotay are left alone on a planet because of a disease" => [%w[VOY Resolutions]],
    "A Krenim timeship erases history while Voyager falls apart over a year" => [%w[VOY Year\ of\ Hell]],
    "Aliens on a planet where time passes faster watch Voyager for centuries" => [%w[VOY Blink\ Of\ An\ Eye]],
    "A museum far in the future tells a false history of Voyager as villains" => [%w[VOY Living\ Witness]],
    "Archer is put on trial by the Klingons" => [%w[ENT Judgment]],
    "Trip becomes pregnant after visiting an alien ship" => [%w[ENT Unexpected]],
    "A clone of Trip is grown to save his life and lives a whole lifetime in days" => [%w[ENT Similitude]]
  }.freeze

  desc "Rank of the right episode for #{EVAL_CASES.size} known scene-search descriptions"
  task eval: :environment do
    ranks = EVAL_CASES.map do |query, targets|
      hits = SemanticSearch.call(query).hits
      hit = hits.find { |h| targets.any? { |series, prefix| h.episode.series == series && h.episode.title.to_s.downcase.start_with?(prefix.downcase) } }
      puts format("%5s  %s%s", hit ? "##{hit.rank}" : "-", query, hit ? "" : "  (top: #{hits.first&.episode&.display_title})")
      hit&.rank
    end

    found = ranks.compact
    n = ranks.size
    puts
    puts "#1: #{found.count(1)}/#{n}   top 3: #{found.count { _1 <= 3 }}/#{n}   top #{SemanticSearch::MAX_EPISODES}: #{found.size}/#{n}"
    puts format("mean reciprocal rank: %.3f (a miss counts as 0)", found.sum { 1.0 / _1 } / n)
  end
end
