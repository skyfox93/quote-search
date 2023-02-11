class DialoguesController < ApplicationController
  before_action :set_dialogue, only: %i[ show edit update destroy ]

  # GET /dialogues or /dialogues.json
  def index
    @dialogues = Dialogue.search(params[:query]).limit(300)
  end

  # GET /dialogues/1 or /dialogues/1.json
  def show
    @dialogue = Dialogue.find(params[:id])
    @text = EpisodeText.where(episode: @dialogue.episode, series: @dialogue.series).first().text
    @with_highlights = @text.gsub("#{@dialogue.character}: #{@dialogue.line[0..20]}", "<span id=#{@dialogue.id} style=\"background-color: yellow\">#{@dialogue.character}:</span> #{@dialogue.line[0..20]}")
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
    def set_dialogue
      @dialogue = Dialogue.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def dialogue_params
      params.require(:dialogue).permit(:line, :episode, :series, :character)
    end
end
