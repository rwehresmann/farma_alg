FactoryGirl.define do
  factory :user do
    email
    name "User"
    password "foobar"

    trait :admin do
      admin true
    end

    trait :super_admin do
      super_admin true
    end
  end
end
