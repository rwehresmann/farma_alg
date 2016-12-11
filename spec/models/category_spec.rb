require 'rails_helper'

describe Category, type: :model do
  describe "Validations -->" do
    let(:category) { build(:category) }

    it "is valid with valid attributes" do
      expect(category).to be_valid
    end

    it "is invalid with empty name" do
      category.name = ""
      expect(category).to_not be_valid
    end
  end

  describe "Relationships -->" do
    it "has many exercises" do
      expect(Category.reflect_on_association(:exercises).macro).to eq(:has_many)
    end
  end

  describe "#check_exercises" do
    context "when have exercises" do
      let(:category) { create(:category, exercises_count: 1) }
      before { category.destroy }

      it "doesn't destroy the category" do
        expect(Category.count).to eq(1)
      end
    end

    context "when haven't exercises" do
      let(:category) { create(:category) }
      before { category.destroy }

      it "doesn't destroy the category" do
        expect(Category.count).to eq(0) 
      end
    end
  end
end
