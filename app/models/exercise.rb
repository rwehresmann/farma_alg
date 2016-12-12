class Exercise
  include Mongoid::Document
  include Mongoid::Timestamps

  VALID_DEPENDENCIES = [:or, :and]

  field :title, type: String
  field :content, type: String
  field :available, type: Boolean, default: false
  field :position, type: Integer
  # Score to receive after answer correctly the exercise.
  field :score, type: Integer, default: 10
  # Dependencies are a hash with two keys: :or and :and.
  field :dependencies, type: Hash, default: {}

  default_scope desc(:position)
  #default_scope order_by([:position, :desc])

  before_create :set_position

  attr_accessible :id, :title, :content, :available, :questions_attributes, :category_id, :score

  validates_presence_of :title, :content, :score
  validates :available, :inclusion => {:in => [true, false]}
  validate :validate_dependencies

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

  def validate_dependencies
    if dependencies.keys - VALID_DEPENDENCIES != []
      errors.add(:category, "Invalid dependencie key! Note that only #{format_to_plain(VALID_DEPENDENCIES)} are allowed.")
    end
  end

  def format_to_plain(array)
    array.map{ |i| i }.join(", ")
  end
end
