Random notes relevant to the project:

## Puma ##

-- Most of this is irrelevant given Rake Hijack. Where have I been the last year or two?? --


Reactor:73 >> Raw input sent to app pool?
>   begin
>     if c.try_to_finish
>     @app_pool << c
>     sockets.delete c
>   end

ThreadPool:92 >> work item (from reactor) pulled off queue and handed to Pool's @block.
>       work = todo.shift if continue
>     end
>
>     break unless continue
>
>     block.call(work, *extra)
>   end

Server:240 >> "client" argument is actually a work-item... probably a socket connection?


Binder: sets up the actual listening socket (or whatever) connections, and makes them available to 
    Server through Binder#ios. Has methods like #add_ssl_listener(), #add_socket_listener(), etc.


Server#run
  - sets up thread pools, reactor, etc, then calls #handle_servers.
  
  #handle_servers
    - does a SELECT on the multiple listening sockets. When one is triggered:
    - accept non-block if possible; wrap in Client and handed to thread_pool.
    
  ThreadPool#block <Accepts Client>
    - if the client happens to be ready. "process it".
    - otherwise, add it to the Reactor.
    
  Reactor#add:
    - adds the client to the list of sockets being SELECT'd on
    - sends a message through the ready<->trigger pipe
        - ready is also being
    
    
Server#process_client and Server#handle_request ... these are the points to override if we want to
take Puma in a completely async, non-rack direction.