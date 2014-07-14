class Dashboard::TeamsController < ApplicationController
  before_filter :authenticate_user!
  before_filter :verify_admin, :only =>[:new, :create,:destroy]

  layout "dashboard"

  def new
    @team = Team.new
  end

  def create
    @team = Team.new(params[:team])
    @team.owner_id = current_user.id
    respond_to do |format|
      if @team.save
        format.html { redirect_to dashboard_teams_available_path, notice: 'Turma criada com sucesso.' }
      else
        format.html { render action: "new" }
      end
    end
  end

  def enroll
    t = Team.find(params[:team][:id])
    unless t.users.include?(current_user)
      if t.code == params[:password]
        t.users << current_user
        t.save!
      else
        @wrong_code_team_id = t.id
      end
    end
    @teams = Team.all

    redirect_to dashboard_teams_available_path
  end

  def unenroll
    @team = Team.find(params[:id])

    if @team.users.include?(current_user)
      @team.user_ids = @team.user_ids - [current_user.id]
      @team.save!
    end

    redirect_to dashboard_teams_available_path
  end

  def destroy
    @team = Team.find(params[:id])

    if @team.owner_id == current_user.id
      @team.destroy
    end

    redirect_to dashboard_teams_available_path
  end

  def available
    @teams = Team.all
  end

end