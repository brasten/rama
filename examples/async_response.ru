require 'the_metal'
require 'the_metal/response'

def fibonacci( n )
  return  n  if ( 0..1 ).include? n
  ( fibonacci( n - 1 ) + fibonacci( n - 2 ) )
end

rama_action = ->(req, res) {
  Concurrent::Next::Future.execute(:io) {
    fibonacci(36)
  }.then { |result|
    res.write_head 200, 'Content-Type' => 'application/xml'
    res.write "<fib>#{result}</fib>"
    res.finish
  }
}

require 'the_metal/puma'

# app = TheMetal.build_app [], [], rama_action
server = TheMetal.create_server rama_action
server.listen 9292, '0.0.0.0'