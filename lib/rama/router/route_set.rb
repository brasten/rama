require 'rack/mount'

module Rama::Router
    
  # For now, Rack::Mount::RouteSet provides a lot of the raw functionality.
  #
  # Just embrace and extend; maybe re-implement when it makes sense to.
  #
  class RouteSet < Rack::Mount::RouteSet
    
    # @see Rack::Mount::RouteSet#call
    #
    # We removed any processing of the app results, since it's no longer
    # a Rack response tuple. Could be anything at the moment; will probably
    # be a specific Response OBJECT eventually.
    #
    def call(req)
      raise 'route set not finalized' unless @recognition_graph
      
      recognize(req) do |route, matches, params|
        params.each { |k, v| params[k] = Utils.unescape_uri(v) if v.is_a?(String) }
        
        if route.prefix?
          req[Prefix::KEY] = matches[:path_info].to_s
        end
        
        req[@parameters_key] = (req[@parameters_key] || {}).merge(params)
        
        return route.app.call(req)
      end
    end
    
    VERBS = %w(get post put delete head options patch trace)
    
    VERBS.each do |verb|
      define_method(verb.to_sym) do |path, to:|
        add_route( to, {request_method:verb.upcase, path_info:path }, {}, path )
      end
    end
  end
end
