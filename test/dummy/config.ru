# Copyright (c) 2012-2017 Regents of the University of Minnesota
#
# This file is part of the Minnesota Population Center's IPUMS Terra Project.
# For copyright and licensing information, see the NOTICE and LICENSE files
# in this project's top-level directory, and also on-line at:
#   https://github.com/mnpopcenter/ipums-terra-raster-clipper

# This file is used by Rack-based servers to start the application.


require ::File.expand_path('../config/environment', __FILE__)
run Rails.application
