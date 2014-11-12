require 'the_metal'
require 'the_metal/response'
require 'rama'
require 'concurrent-ruby/next'

include ConcurrentNext

def fibonacci( n )
  return  n  if ( 0..1 ).include? n
  ( fibonacci( n - 1 ) + fibonacci( n - 2 ) )
end

class RamaLogger < Concurrent::Actor::Context
  def on_message(message)
    puts message
  end
end

logger = RamaLogger.spawn(:logger)

$next_request_id = 1

rama_action = ->(req, res) {
  req_id = $next_request_id
  $next_request_id += 1

  logger << ">> ##{req_id} >> Entering Handler"
  future(:io) {
    logger << "   ##{req_id} :: Calculating fibonacci"
    fibonacci(36)
  }.then { |result|
    logger << "   ##{req_id} :: Writing response"
    res.write_head 200, 'Content-Type' => 'application/xml'
    res.write "<fib>#{result}</fib>"
    res.finish
    logger << "   ##{req_id} ** DONE."
  }
  logger << "<< ##{req_id} << Returning from handler."
}

require 'the_metal/puma'

# app = TheMetal.build_app [], [], rama_action
server = TheMetal.create_server rama_action
server.listen 9292, '0.0.0.0'