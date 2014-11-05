require 'rack'
require_relative '../../concurrent-ruby/next'
require 'thread'

module Rama
  module Rack
    class RackAdapter
      include Concurrent::Next

      # If an executor is not provided, this one will be instantiated
      # and used.
      #
      # A new executor is created for EACH INSTANCE of RackAdapter, currently.
      #
      # TODO[bls]: is this really what we want?
      #
      DEFAULT_EXECUTOR = Concurrent::ThreadPoolExecutor.new(
          min_threads: [2, Concurrent.processor_count].max,
          max_threads: Concurrent.processor_count * 100,
          idletime:    60,
          max_queue:   0
        )

      # @param [#call] action
      #
      def initialize(action, executor=nil)
        @executor = executor || DEFAULT_EXECUTOR
        @action   = action
      end

      def call(env)
        res = dispatch_to_action(env)

        if res.kind_of?(Concurrent::Next::Future)
          response_headers = {}
          response_headers["rack.hijack"] = lambda do |io|
            res.then(@executor) { |final_response|
              Concurrent::Next::Future.execute(DEFAULT_EXECUTOR) {
                final_response.body.each do |l|
                  io.puts l
                end
              }.on_completion! {
                io.close
              }
            }.rescue { |err|
              puts err.inspect
            }
          end

          [200, response_headers, nil]
        elsif res.respond_to?(:finalize)
          puts "Nope, just a synchro- response."
          res.finalize
        else
          raise StandardError, "WTF?"
        end
      end

      private

      def dispatch_to_action(env)
        req = ::Rack::Request.new(env)

        @action.(req)
      end


    end
  end
end