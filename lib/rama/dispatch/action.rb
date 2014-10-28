module Rama::Dispatch
  class Action

    def call(req)

    end

  end
end



MyAction = ->(req, res) {
  future { inner_action[req, res] }
}
