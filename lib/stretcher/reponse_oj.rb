# frozen_string_literal: true

require 'oj'

module Faraday
  class Response
    # Response middleware that parses the body as JSON.
    class Oj < Middleware
      def initialize(app = nil, parser_options: nil, content_type: /\bjson$/, preserve_raw: false, symbolize_keys: false)
        super(app)
        @parser_options = parser_options
        @content_types = Array(content_type)
        @preserve_raw = preserve_raw
        @symbolize_keys = symbolize_keys
      end

      def on_complete(env)
        process_response(env) if parse_response?(env)
      end

      private

      def process_response(env)
        env[:raw_body] = env[:body] if @preserve_raw
        env[:body] = parse(env[:body])
      rescue StandardError, SyntaxError => e
        raise Faraday::ParsingError.new(e, env[:response])
      end

      def parse(body)
        options = (@parser_options || {}).merge(mode: :compat, symbol_keys: @symbolize_keys)
        ::Oj.load(body, options) unless body.strip.empty?
      end

      def parse_response?(env)
        process_response_type?(env) &&
          env[:body].respond_to?(:to_str)
      end

      def process_response_type?(env)
        type = response_type(env)
        @content_types.empty? || @content_types.any? do |pattern|
          pattern.is_a?(Regexp) ? type.match?(pattern) : type == pattern
        end
      end

      def response_type(env)
        type = env[:response_headers][CONTENT_TYPE].to_s
        type = type.split(';', 2).first if type.index(';')
        type
      end
    end
  end
end

Faraday::Response.register_middleware(oj: Faraday::Response::Oj)