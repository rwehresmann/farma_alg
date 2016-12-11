require 'rails_helper'

describe Exercise, type: :model do
  describe "Validations -->" do
    let(:exercise) { build(:exercise) }

    it "is valid with valid attributes" do
      expect(exercise).to be_valid
    end

    it "is valid with valid dependencie keys" do
      exercise.dependencies = { and: [], or: [] }
      expect(exercise).to be_valid
    end

    it "is invalid with an invalid dependencie key" do
      exercise.dependencies = { test: [] }
      expect(exercise).to_not be_valid
    end

    it "is invalid with empty score" do
      exercise.score = ""
      expect(exercise).to_not be_valid
    end

    it "is invalid with empty content" do
      exercise.content = ""
      expect(exercise).to_not be_valid
    end

    it "is invalid with empty title" do
      exercise.title = ""
      expect(exercise).to_not be_valid
    end
  end

  describe "Relationships -->" do
    it "belongs to a category" do
      expect(Exercise.reflect_on_association(:category).macro).to eq(:belongs_to)
    end
  end
end
