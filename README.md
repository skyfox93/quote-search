# README

## Trek Search
  This is a basic Ruby on Rails/ Postgres App utitlizing demonstrating Postgres's fulll text search functions demontrated through star trek quotes.
  Users can search using key words like 'beam me up', utilize quotes "beam me up" for an exact phrase match, and use "OR" statements, e.g "beam me up" OR "beam me down".
  
 Data is from Kaggle and may not be complete.
 Data sources here:<br>
 [Quotes dataset](https://www.kaggle.com/datasets/manann/quotes-500k)
 <br>
 [Star Trek Dataset](https://www.kaggle.com/datasets/gjbroughton/start-trek-scripts)
 
 ## To Run
 (you should have Ruby installed)
 `bundle install`
 
 
 `rails db:migrate`
 
 `rails db:seed`
 
 `rails s`

 ## Describe-a-scene search (AI)
 "Describe a scene" (`/episode_texts`) finds episodes from a description, e.g. "Geordi is brainwashed into becoming an assassin". It needs an OpenAI API key in `.env`:

 `OPENAI_API_KEY=...`

 Then embed the transcripts (TNG by default; `SERIES=all` for everything):

 `bin/rails seed_embedding`

 How a search works:
 1. The query is embedded exactly as typed and matched against transcript chunks with pgvector (`?series=TNG` limits it to one series). Each chunk is one scene: transcripts are cut at every location marker (`[Bridge]`), scenes under 400 characters are merged into the next, and the few over 3,000 characters are split on line breaks with a little overlap.
 2. The 40 nearest chunks are grouped by episode, and each episode is scored by the average similarity of its top three (missing ones count as 0, so one close match alone can't win). Episodes are ranked by that score, each with its best-matching scenes.
 3. The results page loads straight away; results arrive in a Turbo Frame, then an AI summary of the top results streams in above them.
 4. Separately, a chat model suggests a tidier search under the search box: the request phrasing ("in what episode does...") removed, and a series filter if one is named ("in TNG"). It's only a link, never applied for you. It may only remove words: anything it adds is dropped, so its own Star Trek knowledge (episode titles, real dialogue) never reaches the search.

 Suggestions, embeddings and AI summaries are cached in `Rails.cache`, so repeat searches skip OpenAI. Optional settings:
 `OPENAI_SEARCH_MODEL` / `OPENAI_SEARCH_REASONING` (default `gpt-5.4-mini` / `none`) and
 `OPENAI_SUMMARY_MODEL` / `OPENAI_SUMMARY_REASONING` (default `gpt-5.4-nano` / `none`). The summary model is deliberately small and told to use only the retrieved excerpts, so the answer shows what retrieval found rather than what the model already knows about Star Trek.

 ## Ask a question (AI agent with SQL)
 "Ask a question" (`/ask`) gives an OpenAI model two tools and lets it use them until it can answer: `run_sql` queries the `dialogues` and `episode_texts` tables (e.g. "Which TNG character has the most lines?"), and `search_scenes` runs the vector search to find episodes by what happens in them, which it can then follow up with SQL. Every step and its results are shown as it works.

 The SQL is untrusted, so the boundary is Postgres itself: `ReadonlySql` runs it on its own connection (`AgentRecord`, the `agent` entry in `config/database.yml`) that logs in as `search_agent_reader`, a role that can only SELECT those two tables. Postgres then refuses writes, other tables and superuser functions, however the SQL is written. `ReadonlySql` only adds what privileges can't: the query is wrapped as a subquery (one SELECT, at most 50 rows), with a 4s timeout, in a transaction that is always rolled back.

 The migrations create the role, grant it SELECT and let it log in:

 `bin/rails db:migrate`

 Locally, Postgres usually trusts local logins. Where it needs a password (production), set one with `ALTER ROLE search_agent_reader PASSWORD '...'` and give the app the same value in `SEARCH_AGENT_DB_PASSWORD`.

 Optional settings: `OPENAI_AGENT_MODEL` / `OPENAI_AGENT_REASONING` (default `gpt-5.4-mini` / `low`).

 The home page (`/`) is a write-up comparing the three levels (keyword search, RAG, agent). Each has a snapshot of a real example (in `app/views/home/_*_example.html.erb`, so the page makes no API calls) and a search box to try it live.

 ## Dialogue lines and character names
 `db/seeds.rb` parses each raw transcript with `TranscriptParser` (a speech starts with `NAME:` at the start of a line, so one-letter speakers like Q are kept; stage directions, locations and narration become `SCENE` rows) and standardizes speakers with `CharacterName` (`PICARD [OC]` becomes `PICARD`, with `OC` in `delivery`; the name as written stays in `character_raw`).

 To re-parse the dialogues in an existing database without touching episodes or embeddings (dialogue ids change):

 `bin/rails dialogues:rebuild`

 `bin/rails characters:list` writes every name, raw and standardized, to `tmp/character_names.csv`.
