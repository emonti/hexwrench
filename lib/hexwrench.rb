begin
  require 'rubygems'
rescue LoadError
end

module Hexwrench
  VERSION = "0.1.0"
end
require 'wx'
require 'hexwrench/edit_window'
require 'hexwrench/gui.rb' # gui.rb provides  EditFrame's layout from XRC
require 'hexwrench/edit_frame'
require 'hexwrench/data_inspector'
require 'hexwrench/stringsvlist'
