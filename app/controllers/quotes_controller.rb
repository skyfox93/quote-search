class QuotesController < ApplicationController

        def index
            @quotes = Quote.search(params[:query]).limit(100)
        end
end
