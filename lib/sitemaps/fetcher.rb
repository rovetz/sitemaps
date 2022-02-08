module Sitemaps
  # Simple single purpose HTTP client. Uses `Net::HTTP` directly, so as to not incur dependencies.
  module Fetcher
    class FetchError       < StandardError; end
    class MaxRedirectError < StandardError; end

    @max_attempts = 10

    # Fetch the given URI.
    #
    # Handles redirects (up to 10 times), and additionally will inflate a body delivered without
    # a content-encoding header, but with a `.gz` as the end of the path.
    #
    # @param uri [String, URI] the URI to fetch.
    # @return [String]
    # @raise [FetchError] if the server responds with an HTTP status that's not 2xx.
    # @raise [MaxRedirectError] if more than 10 redirects have occurred while attempting to fetch the resource.
    def self.fetch(uri)
      attempts = 0

      # we only work on URI objects
      unless uri.is_a? URI
        uri = "http://#{uri}" unless uri =~ %r{^https?://}
        uri = URI.parse(uri)
      end

      until attempts >= @max_attempts
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE

        request = Net::HTTP::Get.new(uri.request_uri)

        resp = http.request(request)
        
        # resp = Net::HTTP.get_response(uri)

        # on a good 2xx response, return the body
        if resp.code.to_s =~ /2\d\d/
          if resp.header["Content-Encoding"].blank? && uri.path =~ /\.gz$/
            return Zlib::GzipReader.new(StringIO.new(resp.body)).read
          else
            return resp.body
          end

        # on a 3xx response, handle the redirect
        elsif resp.code.to_s =~ /3\d\d/
          location = URI.parse(resp.header['location'])
          location = uri + resp.header['location'] if location.relative?

          uri       = location
          attempts += 1
          next

        # otherwise (4xx, 5xx) throw an exception
        else
          raise FetchError, "Failed to fetch URI, #{uri}, failed with response code: #{resp.code}"
        end
      end

      # if we got here, we ran out of attempts
      raise MaxRedirectError, "Failed to fetch URI #{uri}, redirected too many times" if attempts >= @max_attempts
    end
  end
end
