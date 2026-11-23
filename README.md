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
