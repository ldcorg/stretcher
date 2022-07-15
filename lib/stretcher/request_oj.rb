# frozen_string_literal: true

require 'oj'

module Faraday
  class Request
    # Request middleware that encodes the body as JSON.
    class Oj < Middleware
      MIME_TYPE = 'application/json'
      MIME_TYPE_REGEX = %r{^application/(vnd\..+\+)?json$}.freeze

      def initialize(app = nil, dump_options: nil)
        super(app)
        @dump_options = dump_options
      end

      def on_request(env)
        match_content_type(env) do |data|
          env[:body] = encode(data)
        end
      end

      private

      def encode(data)
        options = (@dump_options || {}).merge(mode: :compat)
        ::Oj.dump(data, options)
      end

      def match_content_type(env)
        return unless process_request?(env)

        env[:request_headers][CONTENT_TYPE] ||= MIME_TYPE
        yield env[:body] unless env[:body].respond_to?(:to_str)
      end

      def process_request?(env)
        type = request_type(env)
        body?(env) && (type.empty? || type.match?(MIME_TYPE_REGEX))
      end

      def body?(env)
        (body = env[:body]) && !(body.respond_to?(:to_str) && body.empty?)
      end

      def request_type(env)
        type = env[:request_headers][CONTENT_TYPE].to_s
        type = type.split(';', 2).first if type.index(';')
        type
      end
    end
  end
end

Faraday::Request.register_middleware(oj: Faraday::Request::Oj)