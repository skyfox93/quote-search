# README

## Trek Reads Search
  This is a basic ruby on Rails application utitlizing full text search for good reads and star trek quotes.
  Users can search using key words like 'beam me up', utilize quotes "beam me up" for an exact phrase match, and use "OR" statements, e.g "beam me up" OR "beam me down".
  
 Data is from Kaggle and may not be complete.
 Data sources here:
 https://www.kaggle.com/datasets/manann/quotes-500k
 https://www.kaggle.com/datasets/gjbroughton/start-trek-scripts
 
 ## To Run
 (you should have Ruby installed)
 `bundle install`
 
 
 `rails db:migrate`
 
 `rails db:seed`
 
 `rails s`
