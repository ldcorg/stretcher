require 'thread'
require 'logger'
require 'hashie'
require 'oj'
require 'faraday'
require "stretcher/version"
require 'stretcher/request_error'
require 'stretcher/search_results'
require 'stretcher/es_component'
require 'stretcher/server'
require 'stretcher/index'
require 'stretcher/index_docs'
require 'stretcher/alias'
require 'stretcher/cluster'
require 'stretcher/util'
require 'stretcher/smash'

module Stretcher
  Oj.default_options = { :mode => :compat }
end
