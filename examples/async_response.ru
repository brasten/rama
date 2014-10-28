require 'rack'
require 'rama/dispatch'
require 'rama/rack'
require_relative '../vendor/vendor'

def fibonacci( n )
  return  n  if ( 0..1 ).include? n
  ( fibonacci( n - 1 ) + fibonacci( n - 2 ) )
end

rama_action = ->(req) {
  Concurrent::Next::Future.execute(:io) {
    fib_result = fibonacci(35)

    Rack::Response.new(<<-EOM.split
<html>
  <head>
    <title>YAY!</title>
  </head>
  <body>
    #{fib_result}
    lskjdlkfjsldkj
    skldjflsk
    lksdjf
  </body>
</html>
      EOM
    )
  }
}

adapter = Rama::Rack::RackAdapter.new(rama_action)

run adapter