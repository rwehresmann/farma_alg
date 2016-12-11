class Category
  include Mongoid::Document
  include Mongoid::Timestamps

  before_destroy :check_exercises

  field :name, type: String
  has_many :exercises

  validates_presence_of :name

  private

    def check_exercises
      if exercises.count > 0
        errors.add(:base, "Cannot delete category while exercises whit this category exists.")
        return false
      end
    end
end
