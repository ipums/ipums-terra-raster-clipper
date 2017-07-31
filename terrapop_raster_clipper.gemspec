$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require "terrapop_raster_clipper/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "terrapop_raster_clipper"
  s.version     = TerrapopRasterClipper::VERSION
  s.authors     = ["Will Lane"]
  s.email       = ["wwlane@umn.edu"]
  s.summary     = "Clip rasters to geographic boundaries"
  s.description = "Retrieve data and prepare image files for delivery to the main webapp or the extract engine"
  s.license     = "MIT"

  s.files = Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.rdoc"]
  s.test_files = Dir["test/**/*"]

  s.add_dependency "rails", "~> 4.2.6"

  s.add_development_dependency "activerecord-jdbcsqlite3-adapter"
end
