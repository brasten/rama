# Rama #

This isn't really a thing. It's a from-scratch, hobby-ish project. The kind of thing you'd
be stupid to build yourself because there are dozens available already.

The aim of this project is to build yet another web framework. Really more of a toolkit for API services. 

## Goals ##

 * Solve all the nitpicks I've had with every other framework
 * Make async possible, easy, and by default. Invisible in most cases, but highly customizable
   when needed.
 * Targeted at backend/API server development, not so much web development
 * Less DSL-ish; more PORO-ish
 * Less monolithic; more toolbox-ish

 
### Inspirations ###

Most of the inspiration comes from Ruby itself, and wanting a service framework lets you write
more of your code in pure Ruby and less in framework DSLs. Other inspirations:
 
  * Scala futures and how they enable simple, high-performant async code
  * The Play framework; specifically the parts that build upon futures for async responses
  * Merb; specifically the focus of less magic, more straight-forward code
 
 
### Design Decisions ###

These can and will change as needed to meet the project goals. I welcome feedback.
 
 * Build heavily on Concurrent-Ruby gem. I'd love to support Celluloid as well -- in fact I'd consider support for it
   critical at the application-layer. But the concurrent-ruby gem is a better fit for Rama internals.
 * Package and deploy apps as Rubygems??? I'm sure someone's considered this -- would love feedback. Seems like
   a decent way to deploy services.
 
### Sub-projects ###

 * rama-dispatch: routing and basic request/response handling. This will probably be broken up into rama-routing
     and something else eventually.
 * rama-metrics: (not yet implemented) metrics and event gathering -- similar to, or perhaps derived from, Puma's Event.
 * rama-config: (not yet implemented) App configuration as a first-class citizen. Should be able to pull configuration
     from the project, from a system directory, as well as environment variables.