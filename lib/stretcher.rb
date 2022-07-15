require 'thread'
require 'logger'
require 'oj'
require 'faraday'
require 'stretcher/reponse_oj'
require 'stretcher/request_oj'
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

module Stretcher
  Oj.default_options = { mode: :compat }
end
