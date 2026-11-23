class QuotesController < ApplicationController
  def index
    @quotes = params[:query].present? ? Quote.search(params[:query]).limit(100) : Quote.none
  end
end
