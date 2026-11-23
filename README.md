# README

## Trek Reads Search
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
 1. A chat model rewrites the description as a few lines of plausible script, guesses likely episodes, and spots a series filter ("in TNG").
 2. That passage and the user's own words are embedded and matched against transcript chunks with pgvector.
 3. Both rankings and the guesses are merged (reciprocal rank fusion) into a list of episodes with their best-matching scenes.
 4. The results page loads straight away; results arrive in a Turbo Frame, then an AI answer streams in above them.

 Query plans, embeddings and AI answers are cached in `Rails.cache`, so repeat searches skip OpenAI. Optional settings:
 `OPENAI_SEARCH_MODEL` / `OPENAI_SEARCH_REASONING` (default `gpt-5.4-mini` / `low`) and
 `OPENAI_SUMMARY_MODEL` / `OPENAI_SUMMARY_REASONING` (default `gpt-5.4-mini` / `none`).

 ## Ask a question (AI agent with SQL)
 "Ask a question" (`/ask`) gives an OpenAI model one tool, `run_sql`, and lets it query the `dialogues` and `episode_texts` tables until it can answer (e.g. "Which TNG character has the most lines?"). Every query and its results are shown as it works.

 The SQL is untrusted, so `ReadonlySql` runs it with several guards: a single SELECT, no comments or file/SQL-executing functions, a read-only transaction with a 4s timeout that is always rolled back, an `EXPLAIN` check that only those two tables are read, and at most 50 rows. For a hard boundary, run the migration that creates the `search_agent_reader` role (SELECT on those two tables only); queries then run as that role:

 `bin/rails db:migrate`

 Optional settings: `OPENAI_AGENT_MODEL` / `OPENAI_AGENT_REASONING` (default `gpt-5.4-mini` / `low`).

 The home page (`/`) compares the three levels (keyword search, RAG, agent) with a live example of each.

 ## Dialogue lines and character names
 `db/seeds.rb` parses each raw transcript with `TranscriptParser` (a speech starts with `NAME:` at the start of a line, so one-letter speakers like Q are kept; stage directions, locations and narration become `SCENE` rows) and standardizes speakers with `CharacterName` (`PICARD [OC]` becomes `PICARD`, with `OC` in `delivery`; the name as written stays in `character_raw`).

 To re-parse the dialogues in an existing database without touching episodes or embeddings (dialogue ids change):

 `bin/rails dialogues:rebuild`

 `bin/rails characters:list` writes every name, raw and standardized, to `tmp/character_names.csv`.
