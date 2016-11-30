class Exercise
  include Mongoid::Document
  include Mongoid::Timestamps

  field :title, type: String
  field :content, type: String
  field :available, type: Boolean, default: false
  field :position, type: Integer
  # Points to receive after answer correctly the exercise.
  field :points, type: Integer, default: 10

  default_scope desc(:position)
  #default_scope order_by([:position, :desc])

  before_create :set_position

  attr_accessible :id, :title, :content, :available, :questions_attributes, :category_id

  validates_presence_of :title, :content
  validates :available, :inclusion => {:in => [true, false]}

  belongs_to :lo
  belongs_to :category

  has_many :questions, dependent: :delete

  def delete_last_answers_of(user_id)
    self.questions.each  do |question|
      question.last_answers.where(user_id: user_id).try(:delete_all)
      question.tips_counts.where(user_id: user_id).try(:delete_all)
    end
  end

  def questions_avaiable
    self.questions.where(available: true)
  end

private
  def set_position
    self.position = Time.now.to_i
  end
end
