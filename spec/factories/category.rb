FactoryGirl.define do
  factory :category do
    name

    ignore do
      exercises_count 0
    end

    after(:create) do |category, evaluator|
      create_list(:exercise, evaluator.exercises_count, category: category)
    end
  end
end
