require 'math_evaluate'
require 'judge'

include ActionView::Helpers::TextHelper

class Answer

  include Mongoid::Document
  include Mongoid::Timestamps
  include MathEvaluate
  include Judge

  field :response
  field :correct, type: Boolean
  field :results, type: Hash
  field :for_test, type: Boolean
  field :compile_errors
  field :try_number, type: Integer
  field :lang

  field :lo, type: Hash
  field :exercise, type: Hash
  field :question, type: Hash
  field :team, type: Hash

  field :team_id, type: Moped::BSON::ObjectId
  field :lo_id, type: Moped::BSON::ObjectId
  field :exercise_id, type: Moped::BSON::ObjectId
  field :question_id, type: Moped::BSON::ObjectId

  alias :super_exercise :exercise
  alias :super_question :question

  attr_accessible :id, :response, :user_id, :team_id, :lo_id, :exercise_id, :question_id, :for_test, :try_number, :results, :lang

  belongs_to :user
  has_one :last_answer
  embeds_many :comments, :as => :commentable

  #default_scope desc(:created_at)

  scope :wrong, where(correct: false, :team_id.ne => nil, :for_test.ne => true)
  scope :corrects, where(correct: true, :team_id.ne => nil, :for_test.ne => true)
  scope :every, excludes(team_id: nil, for_test: true)

  before_create :verify_response, :store_datas
  after_create :register_last_answer#, :update_questions_with_last_answer

  def self.search(page, params = nil, team_ids = nil)
    if team_ids
      if params
        Answer.excludes(team_id: nil, for_test: true).where(params).in(team_id: team_ids).page(page).per(20)
      else
        Answer.excludes(team_id: nil, for_test: true).in(team_id: team_ids).page(page).per(20)
      end
    else
      if params
        Answer.excludes(team_id: nil, for_test: true).where(params).page(page).per(20)
      else
        Answer.excludes(team_id: nil, for_test: true).page(page).per(20)
      end
    end
  end

  def lo
    @_lo ||= Lo.new(super) rescue nil
  end

  def exercise
    @_exercise ||= Exercise.new(super) rescue nil
  end

  def exercise_as_json
    exercises = super_exercise
    %w(position available lo_id updated_at created_at).each {|e| exercises.delete(e)}
    exercises['questions'].each do |question|
      question['answered'] = question['_id'] == self.question_id
      if question['answered']
        question['last_answer'] = self.as_json
        %w(updated_at exercise lo question team created_at).each {|e| question['last_answer'].delete(e)}
      end
      #else
      #  x = LastAnswer.find_or_create_by(:user_id => self.user_id, :question_id => question['_id'])
      #  if x.answer_id.nil?
      #    question['last_answer'] = nil
      #    x.delete
      #  else
      #    question['last_answer'] = Answer.find(x.answer_id).as_json
      #    %w(updated_at exercise lo question team created_at).each {|e| question['last_answer'].delete(e)}
      #  end
      #end
      %w(position available lo_id updated_at test_cases correct_answer created_at).each {|e| question.delete(e)}
    end
    exercises['questions'].delete_if {|question| not question['answered']}
    exercises
  end

  def question
    @_question ||= Question.new(super) rescue nil
  end

  def question_as_json
    question = super_question
    %w(position available lo_id updated_at test_cases exercise_id correct_answer).each {|e| question.delete(e)}
    question
  end

  def team
    @_team ||= Team.new(super) rescue nil
  end

# Need store all information for retroaction
private
  def store_datas
    question = Question.find(self.question_id)
    self.exercise = question.exercise.as_json(include: {questions: {include: :test_cases }})
    self.lo = question.exercise.lo.as_json
    self.question = question.as_json(include: :test_cases)
    self.team = Team.find(self.team_id).as_json if self.team_id
  end

  def verify_response
    question = Question.find(self.question_id)
    tmp = Time.now.to_i

    compile_result = Judge::compile(self.lang,self.response,tmp)
    
    p compile_result
    $stdout.flush

    if compile_result[0] != 0
      self.compile_errors = compile_result[1]
      self.correct = false      
    else

      correct = Judge::test(lang,compile_result[1],question.test_cases,tmp)
      
      self.results = Hash.new
      self.correct = true
      correct.each do |id,r|

        self.results[id] = Hash.new
        self.results[id][:diff_error] = false
        self.results[id][:time_error] = false
        self.results[id][:exec_error] = false
        self.results[id][:presentation_error] = false
        self.results[id][:output] = r[1]

        if r[0] == 3 
          self.correct = false
          self.results[id][:diff_error] = true
          self.results[id][:content] = question.test_cases.find(id).content
          self.results[id][:tip] = question.test_cases.find(id).tip
        elsif r[0] == 2
          self.correct = false
          self.results[id][:presentation_error] = true
          self.results[id][:content] = question.test_cases.find(id).content
        elsif r[0] == 143
          self.correct = false
          self.results[id][:time_error] = true
        elsif r[0] != 0
          self.correct = false
          self.results[id][:exec_error] = true
          self.results[id][:output2] = simple_format r[1]
        end
      end
    end

    unless self.for_test
      la = LastAnswer.find_or_create_by(:user_id => self.user_id, :question_id => self.question_id)
      self.try_number = 1
      if not la.answer_id.nil?
        self.try_number = la.answer.try_number + 1
      else
        la.delete
      end
    end
  end

  def register_last_answer
    unless self.for_test
      la = LastAnswer.find_or_create_by(:user_id => self.user.id, :question_id => self.question.id)
      la.answer = self
      la.question = self.question
      la.user = self.user
      la.save!
    end
  end

end
