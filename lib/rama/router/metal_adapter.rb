require 'the_metal'
require 'the_metal/request'
require 'the_metal/response'

module Rama::Router
  
  # <dramatic music>
  #
  # The entire Ruby web ecosystem is currently in the throws of confusion and civil-war; lacking any real
  # direction and fragmenting into competing camps.
  #
  # This little hack attempts to restore some harmony (for me) by bridging the Old Way (Rack) to My Way (Rama)
  # through pieces of one of the [other?] possible New Ways (The_Metal).
  #
  # This is a hack right now, but it's a start.
  #
  class MetalAdapter
    def initialize(app)
      @app = app
    end
    
    def call(env)
      req = Rack::Request.new(env)  # TheMetal::Request doesn't work yet
      res = TheMetal::Response.new(200, {}, env['rack.hijack'].call)
      
      # Hacky hacky hacky.
      @app.call(req).instance_eval {
        # If we get anything other than a future back, turn it into a "future" (to simplify callbacks).
        respond_to?(:then) ? self : ConcurrentNext::Future.future(:immediate) { self }
      }.then { |result|
        res.write_head 200, 'Content-Type' => 'application/json'
        res.write result
        res.finish
      }
      
      [-1, {}, []]  # We're going full-async, so dump out of here right away.
    end
  end
end
