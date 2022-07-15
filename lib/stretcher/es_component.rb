module Stretcher
  # Elasticsearch has symmetry across API endpoints for Server, Index, and Type, lets try and provide some common ground
  class EsComponent

    def self.indig(obj, *keys)
      keys.reduce(obj) do |memo, key|
        if memo.respond_to?(:has_key?)
          if memo.has_key?(key)
            memo[key]
          else
            key = key.is_a?(String) ? key.to_sym : key.to_s
            memo[key]
          end
        end
      end
    end

    def indig(obj, *keys)
      self.class.indig(obj, *keys)
    end

    def self.deep_transform_keys(hash)
      result = hash.transform_keys(&:to_sym)
      result.each do |k, v|
        if v.is_a?(Hash)
          result[k] = deep_transform_keys(v)
        elsif v.is_a?(Array)
          result[k] = v.map { |i| i.is_a?(Hash) ? deep_transform_keys(i) : i }
        end
      end
      result
    end

    def deep_transform_keys(hash)
      self.class.deep_transform_keys(hash)
    end

    # Many of the methods marked protected are called by one line shims in subclasses. This is mostly to facilitate
    # better looking rdocs

    def do_search(generic_opts = {}, explicit_body = nil)
      query_opts = {}
      body = nil
      if explicit_body
        query_opts = generic_opts
        body = explicit_body
      else
        body = generic_opts
      end

      response = request(:get, "_search", query_opts, nil, {}) do |req|
        req.body = body
      end
      SearchResults.new(response)
    end

    def do_refresh
      request(:post, "_refresh")
    end

    def request(method, path = nil, params = {}, body = nil, headers = {}, options = {}, &block)
      prefixed_path = path_uri(path)
      raise "Cannot issue request, no server specified!" unless @server
      @server.request(method, prefixed_path, params, body, headers, options, &block)
    end

    def do_delete_query(query, params = {})
      request :post, '_delete_by_query', params do |req|
        req.body = { query: query }
      end
    end

    def do_alias(alias_name_or_prefix)
      request(:get, "_alias/#{alias_name_or_prefix}")
    rescue Stretcher::RequestError::NotFound => e
      return {} if e.http_response.status == 404
      raise e
    end
  end
end
