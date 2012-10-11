require 'rubygems'
require 'math_engine'

module MathEvaluate
  module Expression
    def self.eql?(exp_a, exp_b, options = {})
      begin
        variables = options[:variables] ? options[:variables] : []
        variables_with_values = self.generate_values(options[:variables])

        a = self.evaluate(exp_a.to_s, variables_with_values)
        b = self.evaluate(exp_b.to_s, variables_with_values)

        #puts "exp_a #{exp_a}"
        #puts "exp_b #{exp_b}"
        #puts "a: #{a}"
        #puts "b: #{b}"

        #precission of 6 decimal digits precision
        diff = (a - b).abs
        return  diff < 0.000001
      rescue => e
        puts e
        return false
      end
    end

    def self.evaluate(exp, variables_with_values)
      engine = MathEngine::MathEngine.new
      variables_with_values.each do |key, value|
        engine.evaluate("#{key} = #{value}")
      end
      engine.evaluate(exp)
    end

    def self.generate_values(variables)
      vwv = {}
      variables.each do |v|
        vwv[v] = rand()
      end
      vwv
    end
  end
end