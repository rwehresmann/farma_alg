require 'math_evaluate'
require 'judge'

include ActionView::Helpers::TextHelper

class Answer

  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::Search
  include MathEvaluate
  include Judge


  field :response
  field :changed_correctness, type: Boolean, default: false
  field :changed_correctness_reason
  field :correct, type: Boolean
  field :results, type: Hash
  field :for_test, type: Boolean, default: false
  field :retroaction, type: Boolean, default: false
  field :compile_errors
  field :try_number, type: Integer, default: 1
  field :lang

  field :automatically_assigned_tags, type: Array, default: []
  field :rejected_tags, type: Array, default: []
  field :primary_applied, type: Boolean, default: false

  field :lo, type: Hash
  field :exercise, type: Hash
  field :question, type: Hash
  field :team, type: Hash

  field :team_id, type: Moped::BSON::ObjectId
  field :lo_id, type: Moped::BSON::ObjectId
  field :exercise_id, type: Moped::BSON::ObjectId
  field :question_id, type: Moped::BSON::ObjectId
  field :tag_ids, type: Array


  search_in :response, :compile_errors, :user => :name, :question => :title, :question => :content

  alias :super_exercise :exercise
  alias :super_question :question

  attr_accessible :id, :response, :user_id, :team_id, :lo_id, :exercise_id, :question_id, :for_test, :try_number, :results, :lang, :retroaction

  belongs_to :user, index: true
  has_one :last_answer
  #embeds_many :comments, :as => :commentable
  has_many :comments
  has_many :connections, dependent: :delete
  has_and_belongs_to_many :tags, index: true

  default_scope excludes(team_id:nil)

  scope :has_tag, lambda { |tag_id| where(:tag_ids.in => [tag_id])}
  scope :wrong, where(correct: false, :team_id.ne => nil, :for_test.ne => true)
  scope :corrects, where(correct: true, :team_id.ne => nil, :for_test.ne => true)
  scope :every, excludes(team_id: nil, for_test: true)

  before_create :verify_response,:store_datas
  after_create :register_last_answer,:updateStats,:schedule_process_connections,:update_progress



  def apply_primary_tags
    unless self.primary_applied
      primary_tags = Tag.apply_primary(self)
      primary_tags.each do |tag_id|
        self.tag_ids << tag_id unless self.tag_ids.include?(tag_id)
      end
      self.primary_applied = true
      self.save
    end

    true
  end

  def update_progress
    p = Progress.find_or_initialize_by(team_id:self.team_id,user_id:self.user_id,question_id:self.question_id)
    x = self.calc_progress
    if x > p.value
      p.value = x
    end
    p.save!
  end

  def calc_progress
    p = 0.25
    unless self.compile_errors.nil?
      p = 0.5
    end

    if self.correct
      p = 1.0
    else
      unless self.results.nil?
        p_tc = 0.0
        self.results.each do |id,result|
          unless result['error']
            p_tc = p_tc + 1
          end
        end
        p = p + ((p_tc/self.results.size) * 0.5)
      end
    end

    p
  end

  def similar_answers
    sa = []
    self.connections.each do |c|
      sa << c.target_answer_id
    end

    sa
  end

  def connected_component
    sa = []
    queue = []
    visited = []

    queue.push self.id
    visited.push self.id

    while not queue.empty?
      answer_id = queue.shift

      answer = Answer.find(answer_id)
      sa << answer_id

      for similar_answer in answer.similar_answers do
        unless visited.include?(similar_answer)
          queue.push similar_answer
          visited.push similar_answer
        end

      end
    end
    sa
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

  def question_as_json(user_id)
    question = super_question
    %w(position available lo_id updated_at test_cases exercise_id correct_answer).each {|e| question.delete(e)}
    #question['last_answer']['last_answers'] = Answer.where(user_id: user_id, question_id:question['id']).desc(:created_at).first.as_json
    #question['last_answer']['last_answers'].delete('los_ids')
    #question['last_answer']['last_answers'].delete('question')
    #question['last_answer']['last_answers'].delete('exercise')
    #question['last_answer']['last_answers'].delete('lo')
    #question['last_answer']['last_answers'].delete('team')
    question
  end

  def team
    @_team ||= Team.new(super) rescue nil
  end

  # Need store all information for retroaction
  def store_datas
    question = Question.find(self.question_id)
    self.exercise = question.exercise.as_json(include: {questions: {include: :test_cases }})
    self.lo = question.exercise.lo.as_json
    self.question = question.as_json(include: :test_cases)
    self.team = Team.find(self.team_id).as_json if self.team_id
	true
  end

  def exec
    question = Question.find(self.question_id)
    tmp = Time.now.to_i

    compile_result = Judge::compile(self.lang,self.response,tmp)

    if compile_result[0] != 0
      self.compile_errors = compile_result[1]
      self.correct = false
    else

      correct = Judge::test(lang,compile_result[1],question.test_cases,tmp)

      self.results = Hash.new
      self.correct = true
      correct.each do |id,r|

        self.results[id] = Hash.new
        self.results[id][:error] = false
        self.results[id][:diff_error] = false
        self.results[id][:time_error] = false
        self.results[id][:exec_error] = false
        self.results[id][:presentation_error] = false
        self.results[id][:content] = question.test_cases.find(id).content

        self.results[id][:title] = question.test_cases.find(id).title
        self.results[id][:show_input_output] = question.test_cases.find(id).show_input_output

        if question.test_cases.find(id).show_input_output
          self.results[id][:input] = r[1][0]
          self.results[id][:output_expected] = r[1][1]
        end

        self.results[id][:output] = r[1][2]
        self.results[id][:id] = id

        if r[0] == 3
          self.correct = false
          self.results[id][:error] = true
          self.results[id][:diff_error] = true
        elsif r[0] == 2
          self.correct = false
          self.results[id][:error] = true
          self.results[id][:presentation_error] = true
        elsif r[0] == 143 || r[0] == 141
          self.correct = false
          self.results[id][:error] = true
          self.results[id][:time_error] = true
        elsif r[0] != 0
          self.correct = false
          self.results[id][:error] = true
          self.results[id][:exec_error] = true
        end

        if Answer.where(user_id: self.user_id, question_id: self.question_id, correct: false, compile_errors: nil).count >= question.test_cases.find(id).tip_limit-1 || self.correct
          self.results[id][:tip] = question.test_cases.find(id).tip
        end

        #self.results[id][:output2] = simple_format r[1][0]
      end
    end
    true
  end

  def available_tags
    available_tags = []
    Tag.all.each do |t|
      available_tags << t.name
    end

    tags = []
    self.tags.each do |t|
      tags << t.name
    end

    available_tags - tags
  end

  def verify_response

    self.exec
  end

  def updateStats
    global_stat = Statistic.find_or_create_by(:question_id => self.question_id, :team_id => nil)

    team_stat = Statistic.find_or_create_by(:question_id => self.question_id, :team_id => self.team_id)

    global_stat.updateStats(self)
    team_stat.updateStats(self)

    global_stat.save!
    team_stat.save!
  end

  def previous(n)
    previous_answers = Answer.where(user_id: self.user_id, team_id: self.team_id, question_id: self.question_id).desc(:created_at).lte(created_at: self.created_at)[0..n]

    x = previous_answers.count
    if x > 0
      i = 0
      while i < x - 1
        previous_answers[i]['previous'] = previous_answers[i+1].response.clone
        puts i
        puts previous_answers[i]['previous']
        i = i + 1
      end
      previous_answers[i]['previous'] = ""
    end

    previous_answers
  end

  def self.propagate_properties_to_neigh(answer,neigh_id)
    changed = false
    neigh = Answer.find(neigh_id)
    connections = neigh.connections
    weight = connections[connections.index{|x| x.target_answer_id.to_s == answer.id.to_s}].weight
    naat = neigh.automatically_assigned_tags


    # clean any tag got from answer that answer does not have anymore
    remove = []
    i = 0
    for t in naat do
      if t[2] == answer.id && ((not answer.automatically_assigned_tags.include?(t[0])) && (not answer.tag_ids.include?(t[0])))
        remove << t
      end
      i += 1
    end

    remove.each do |i|
      naat.delete(i)
      changed = true
      tag = Tag.find(i[0])
      puts "Answer(#{answer.id}).aat.#{tag.name} -> (removed) Answer(#{neigh_id}).aat"
    end

    # confirmed tags
    for tag in answer.tags do

      unless tag.primary

        # neigh already has this tag as confirmed
        if neigh.tags.include?(tag)
          # do nothing
        # neigh already has this tag as automatically assigned
        elsif not (i = naat.index{ |x| x[0].to_s == tag.id.to_s }).nil?
          t = naat[i]

          # passed by another answer
          if t[2] != answer.id
            if t[1] < weight
              t[1] = weight
              puts "Answer(#{answer.id}).#{tag.name} -> (substituted) Answer(#{neigh_id}).aat"
              changed = true
            end
          # passed by this answers
          else
            # update if any change
            if t[1] != weight
              t[1] = weight
              puts "Answer(#{answer.id}).#{tag.name} -> (updated) Answer(#{neigh_id}).aat"
              changed = true
            end
          end
        # neigh does not have this tag
        else
          # was it rejected?
          unless neigh.rejected_tags.include?(tag.id.to_s)
            # no
            naat.push [tag.id,weight,answer.id]
            puts "Answer(#{answer.id}).#{tag.name} -> (new) Answer(#{neigh_id}).aat"
            changed = true
          end
        end
      end
    end

    # automatically assigned tags
    for atag in answer.automatically_assigned_tags do
      tag = Tag.find(atag[0])

      unless tag.primary

        # neigh already has this tag as confirmed
        if neigh.tags.include?(tag)
          # do nothing
        # neigh already has this tag as automatically assigned
        elsif not (i = naat.index{ |x| x[0].to_s == tag.id.to_s }).nil?
          t = naat[i]

          # passed by another answer
          if t[2] != answer.id
            if (t[1] < weight*atag[1]) and (weight*atag[1] > 0.5)
              t[1] = weight*atag[1]
              changed = true
              puts "Answer(#{answer.id}).aat.#{tag.name} -> (substituted) Answer(#{neigh_id}).aat"
            end
          # passed by this answers
          else
            # update if any change
            if (t[1] != atag[1] * weight) and (weight*atag[1] > 0.5)
              t[1] = atag[1] * weight
              changed = true
              puts "Answer(#{answer.id}).aat.#{tag.name} -> (updated) Answer(#{neigh_id}).aat"
            end
          end
        # neigh does not have this tag
        else
          unless neigh.rejected_tags.include?(tag.id.to_s)
            if weight*atag[1] > 0.5
              naat.push [tag.id,weight*atag[1],answer.id]
              changed = true
              puts "Answer(#{answer.id}).aat.#{tag.name} -> (new) Answer(#{neigh_id}).aat"
            end
          end
        end
      end
    end

    for rejected in answer.rejected_tags do
      tag = Tag.find(rejected)

      unless tag.primary
        unless (i = naat.index{ |x| x[2].to_s == answer.id.to_s && x[0].to_s == rejected.to_s }).nil?
          naat.delete_at(i)
          puts "Answer(#{answer.id}).aat.#{tag.name} -> (removed) Answer(#{neigh_id}).aat"
          changed = true
        end
      end
    end

    neigh.save!

    unless changed
      puts "Answer.(#{answer.id}) didn't change Answer(#{neigh_id})"
    end

    changed
  end

  def propagate_properties
    queue = []
    visited = []

    queue.push self.id
    #visited.push self.id

    while not queue.empty?
      answer_id = queue.shift

      answer = Answer.find(answer_id)

      puts ">>> #{answer.id}"

      for similar_answer in answer.similar_answers do
        unless visited.include?(similar_answer)
          changed = Answer.propagate_properties_to_neigh(answer,similar_answer)
          if changed
            queue.push similar_answer
          end
        end
      end
      visited.push answer_id
      puts "<<< #{answer.id}"
    end
    true
  end

  def schedule_process_connections
    ProcessQueue.create(:type => "apply_primary_tags",
                        :priority => 1,
                        :params => [self.id])
    ProcessQueue.create(:type => "make_inner_connections",
                        :priority => 2,
                        :params => [self.id])
    ProcessQueue.create(:type => "make_outer_connections",
                        :priority => 5,
                        :params => [self.id])
  end

  def schedule_process_propagate(p = 3)
    ProcessQueue.create(:type => "propagate_properties",
                        :priority => p,
                        :params => [self.id])
  end

  def make_inner_connections
    per_batch = 1000

    inner_neigh = Answer.where(:question_id => self.question_id, :team_id => self.team_id).shuffle[0..99]

inner_neigh.each do |a|
    #0.step(inner_neigh.count, per_batch) do |offset|
     # inner_neigh.limit(per_batch).skip(offset).each do |a|
        if self.id != a.id
          SimilarityMachine::create_connection(self,a)
        end
      #end
   # end
end

    true
  end

  def make_outer_connections
    per_batch = 1000

    outer_neigh = Answer.where(:question_id.ne => self.question_id, :team_id => self.team_id).shuffle[0..99]

outer_neigh.each do |a|
    #0.step(outer_neigh.count, per_batch) do |offset|
     # outer_neigh.limit(per_batch).skip(offset).each do |a|
        if self.id != a.id
          SimilarityMachine::create_connection(self,a)
        end
     # end
    #end
end

    true
  end

  def best_matches(n,user)
    best = []
    connections = []

    self.similar_answers.each do |sa|
      best << Answer.find(sa)
    end

    best.sort_by! do |element|
      element.connections.where(target_answer_id:self.id).first.weight
    end

    best.reverse!

    if user.student? && (not user.admin?)
      best[0..n-1].keep_if { |a| a.user_id == user.id }
    else
      best[0..n-1]
    end

  end

private

  def register_last_answer
    unless self.for_test || self.team_id.nil?
      la = LastAnswer.find_or_create_by(:user_id => self.user_id.to_s, :question_id => self.question_id.to_s)

      unless la.answer_id.nil? || la.answer.nil?
        self.try_number = la.answer.try_number + 1
      end



      self.last_answer = la
      la.answer_id = self.id

	    if la.answer.nil?
	      answers = Answer.where(user_id:la.user_id.to_s, question_id: la.question_id.to_S).desc(:created_at)
        if answers.count > 0
          la.answer_id = answers.first.id
          la.save!
        else
	        la.delete
        end
      else
        la.save!
      end

      self.save

      true
    end

    #unless self.for_test
    #  la = LastAnswer.find_or_create_by(:user_id => self.user.id, :question_id => self.question.id)
    #  la.answer = self
    #  la.question_id = self.question_id
    #  la.user_id = self.user_id
    #  la.save!
    #end
  end

  def self.search_aat(params,user)
    as = Answer.search_without_tags(params,user)

    if user.prof?
      if params.has_key?(:tag_ids)
        as = as.entries.keep_if { |a| not (a.automatically_assigned_tags.collect{|x| x[0].to_s} & params[:tag_ids]).empty? }
      end
    end

    # unless user.admin?
    #   if params.has_key?(:tag_ids)
    #     tag_ids = []
    #     for t in user.all_tags do
    #       if params[:tag_ids].include?(t.id.to_s)
    #         tag_ids << t.id.to_s
    #       end
    #     end
    #     as = as.entries.keep_if { |a| not (a.automatically_assigned_tags.collect{|x| x[0].to_s} & tag_ids).empty? }
    #   end
    # end

    as.first(50)
  end

  def self.search(params,user,page=false)
    as = Answer.search_without_tags(params,user)

    if user.prof?
      if params.has_key?(:tag_ids)
        answer_ids = []
        Tag.find(params[:tag_ids]).each do |t|
          answer_ids += t.answer_ids
        end

        as = as.in(:id.in => answer_ids)
      #  as = Kaminari.paginate_array(as.entries.keep_if { |a| not (a.tag_ids & params[:tag_ids]).empty? })
      end
    end

    # only answers with tags from this user
    # unless user.admin?
    #   if params.has_key?(:tag_ids)
    #     tag_ids = []
    #     for t in user.all_tags do
    #       if params[:tag_ids].include?(t.id.to_s)
    #         tag_ids << t.id.to_s
    #       end
    #     end
    #     as.entries.keep_if! { |a| not (a.tag_ids & tag_ids).empty? }
    #   end
    # end

    if as.blank?
      []
    else
      if page != false
        as.page(page).per(20)
      else
        as
      end
    end
  end

  def self.search_without_tags(params,user)
    if params.has_key?(:query) and params[:query].empty?
      if params.has_key?(:daterange) and params[:daterange].empty?
        if not params.has_key?(:user_ids) and
          not params.has_key?(:team_ids) and
          not params.has_key?(:lo_ids) and
          not params.has_key?(:question_ids) and
          not params.has_key?(:answer_ids) and
          not params.has_key?(:tag_ids)
          return []
        end
      end
    end

    as = Answer.excludes(team_id: nil, for_test: true).desc(:created_at)

    if params.has_key?(:query) and not params[:query].empty?
      as = as.full_text_search(params[:query], match: :all)
    end

    if params.has_key?(:daterange) and not params[:daterange].empty?
      start_date = DateTime.strptime(params[:daterange].split(" - ").first,"%d/%m/%Y %H:%M").change(:offset => "-0300")
      end_date = DateTime.strptime(params[:daterange].split(" - ").last,"%d/%m/%Y %H:%M").change(:offset => "-0300")

      as = as.gte(:created_at => start_date)
      as = as.lte(:created_at => end_date)
    end
    if params.has_key?(:user_ids)
      as = as.in(user_id: params[:user_ids])
    end

    if params.has_key?(:team_ids)
      as = as.in(team_id: params[:team_ids])
    end

    if params.has_key?(:lo_ids)
      as = as.in(lo_id: params[:lo_ids])
    end

    if params.has_key?(:question_ids)
      as = as.in(question_id: params[:question_ids])
    end

    if params.has_key?(:answer_ids)
      as = as.in(id: params[:answer_ids])
    end

    unless user.admin?
      user_ids = []
      for u in user.all_students do
        user_ids << u.id
      end
      as = as.in(user_id: user_ids)

      team_ids = []
      for t in user.all_teams do
        team_ids << t.id
      end
      as = as.in(team_id: team_ids)

      lo_ids = []
      for l in user.all_los do
        lo_ids << l.id
      end
      as = as.in(lo_id: lo_ids)

      question_ids = []
      for q in user.all_questions do
        question_ids << q.id
      end
      as = as.in(question_id: question_ids)

      # if params.has_key?(:tag_ids)
      #   tag_ids = []
      #   for t in user.all_tags do
      #     tag_ids << t.id
      #   end
      #   as = as.in(tag_ids: tag_ids)
      # end

      if user.prof?
        as = as.in(team_id: user.all_team_ids)
      else
        as = as.where(user_id: user.id)
      end

    end

    as
  end

  def self.re_run(user_ids)
    user_ids.each do |u|
      p User.find(u).name
      Answer.where(user_id:u).each do |a|
        unless a.for_test
          a.exec
          a.store_datas
          a.save!
        end
      end
    end

    Statistic.delete_all
    Answer.all.each do |a|
      a.updateStats
    end
  end

  def self.make_timeline(as)
    timeline_items = []

    #as.sort!{|x,y| y.created_at <=> x.created_at}

    i=0
    last = nil

    n = as.count

    while i < n
      current = i

      if last.nil?
        timeline_items << ["new_date",[as[current].created_at]]
        last_new_date = 0
        x = 0
      else
        if as[current].created_at.to_date != as[last].created_at.to_date
          timeline_items[last_new_date] << x
          timeline_items << ["new_date",[as[current].created_at]]
          last_new_date = timeline_items.count - 1
          x = 0
        end
      end

      unless last.nil?
        c = Connection.find_or_initialize_by(:target_answer_id => as[last].id.to_s, :answer_id => as[current].id.to_s)
        unless c.new_record?
          timeline_items << ["comparison",[last,current,c]]
        end
      end

      timeline_items << ["answer",[current]]
      x = x+1

      last = current
      i = i+1
    end
    timeline_items[last_new_date] << x if timeline_items.count > 0
    timeline_items
  end

end
