require 'net/http'
require 'json'

class EpisodeTextsController < ApplicationController
  
    # GET /dialogues or /dialogues.json
    def index
      query = params[:query].to_s.strip
      @results = []
      return if query.blank?

      @plan = SearchQueryPlanner.plan(query)
      @results = EpisodeChunk.semantic_search(@plan.query, limit: 10, filters: @plan.filters)
    rescue OpenaiApi::Error => e
      Rails.logger.error("[semantic search] #{e.message}")
      flash.now[:alert] = "Semantic search is unavailable right now."
    end
  
    # GET /dialogues/1 or /dialogues/1.json
    def show
      @episode = EpisodeText.find(params[:id])
      @episode_text = @episode.text
    end
  
    # GET /dialogues/new
    def new
      @dialogue = Dialogue.new
    end
  
    # GET /dialogues/1/edit
    def edit
    end
  
    # POST /dialogues or /dialogues.json
    def create
      @dialogue = Dialogue.new(dialogue_params)
  
      respond_to do |format|
        if @dialogue.save
          format.html { redirect_to dialogue_url(@dialogue), notice: "Dialogue was successfully created." }
          format.json { render :show, status: :created, location: @dialogue }
        else
          format.html { render :new, status: :unprocessable_entity }
          format.json { render json: @dialogue.errors, status: :unprocessable_entity }
        end
      end
    end
  
    # PATCH/PUT /dialogues/1 or /dialogues/1.json
    def update
      respond_to do |format|
        if @dialogue.update(dialogue_params)
          format.html { redirect_to dialogue_url(@dialogue), notice: "Dialogue was successfully updated." }
          format.json { render :show, status: :ok, location: @dialogue }
        else
          format.html { render :edit, status: :unprocessable_entity }
          format.json { render json: @dialogue.errors, status: :unprocessable_entity }
        end
      end
    end
  
    # DELETE /dialogues/1 or /dialogues/1.json
    def destroy
      @dialogue.destroy
      respond_to do |format|
        format.html { redirect_to dialogues_url, notice: "Dialogue was successfully destroyed." }
        format.json { head :no_content }
      end
    end
  
    private
      # Use callbacks to share common setup or constraints between actions.
  
      # Only allow a list of trusted parameters through.
      def dialogue_params
        params.require(:dialogue).permit(:line, :episode, :series, :character)
      end
  end
  