# -*- encoding: utf-8 -*-

$LOAD_PATH.unshift File.expand_path("../lib", __FILE__)
require "rama/version"

Gem::Specification.new do |s|
  s.name        = "rama"
  s.version     = Rama::VERSION
  s.platform    = Gem::Platform::RUBY
  s.license     = "MIT"
  s.authors     = ["Brasten Sager"]
  s.email       = "brasten@brasten.me"
  s.homepage    = "http://not.yet.a.thing"
  s.summary     = "rama-#{Rama::VERSION}"
  s.description = "Ruby web framework"

  s.files            = `git ls-files -- lib/*`.split("\n")
  s.test_files       = `git ls-files -- {spec,features}/*`.split("\n")
  s.extra_rdoc_files = [ "Readme.md" ]
  s.rdoc_options     = ["--charset=UTF-8"]
  s.require_path     = "lib"

  s.add_runtime_dependency "concurrent-ruby"
  s.add_runtime_dependency "the_metal"
  # because the_metal requires it.
  s.add_runtime_dependency "rack"


  s.add_development_dependency "rake"
  s.add_development_dependency "rspec", ">= 3.1"
  s.add_development_dependency "rspec-mocks", ">= 3.1"
  s.add_development_dependency "simplecov"
  s.add_development_dependency "guard-rspec"

end
