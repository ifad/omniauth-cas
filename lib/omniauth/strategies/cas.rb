require 'omniauth'
require 'addressable/uri'

module OmniAuth
  module Strategies
    class CAS
      include OmniAuth::Strategy

      # Custom Exceptions
      class MissingCASTicket < StandardError; end
      class InvalidCASTicket < StandardError; end
      class MissingReturnURL < StandardError; end
      class InvalidReturnURL < StandardError; end

      autoload :ServiceTicketValidator, 'omniauth/strategies/cas/service_ticket_validator'
      autoload :LogoutRequest, 'omniauth/strategies/cas/logout_request'

      attr_accessor :raw_info
      alias_method :user_info, :raw_info

      option :name, :cas # Required property by OmniAuth::Strategy

      option :host, nil
      option :port, nil
      option :path, nil
      option :ssl,  true
      option :service_validate_url, '/serviceValidate'
      option :login_url,            '/login'
      option :logout_url,           '/logout'
      option :on_single_sign_out,   Proc.new {}
      # A Proc or lambda that returns a Hash of additional user info to be
      # merged with the info returned by the CAS server.
      #
      # @param [Object] An instance of OmniAuth::Strategies::CAS for the current request
      # @param [String] The user's Service Ticket value
      # @param [Hash] The user info for the Service Ticket returned by the CAS server
      #
      # @return [Hash] Extra user info
      option :fetch_raw_info,       Proc.new { Hash.new }
      # Make all the keys configurable with some defaults set here
      option :uid_field, 'user'
      option :name_key, 'name'
      option :email_key, 'email'
      option :nickname_key, 'user'
      option :first_name_key, 'first_name'
      option :last_name_key, 'last_name'
      option :location_key, 'location'
      option :image_key, 'image'
      option :phone_key, 'phone'

      # As required by https://github.com/intridea/omniauth/wiki/Auth-Hash-Schema
      AuthHashSchemaKeys = %w{name email nickname first_name last_name location image phone}
      info do
        prune!({
          name: raw_info[options[:name_key].to_s],
          email: raw_info[options[:email_key].to_s],
          nickname: raw_info[options[:nickname_key].to_s],
          first_name: raw_info[options[:first_name_key].to_s],
          last_name: raw_info[options[:last_name_key].to_s],
          location: raw_info[options[:location_key].to_s],
          image: raw_info[options[:image_key].to_s],
          phone: raw_info[options[:phone_key].to_s]
        })
      end

      extra do
        prune!(
          raw_info.delete_if{ |k,v| AuthHashSchemaKeys.include?(k) }
        )
      end

      uid do
        raw_info[options[:uid_field].to_s]
      end

      credentials do
        prune!({ ticket: @ticket })
      end

      def callback_phase
        if on_sso_path?
          single_sign_out_phase
        else
          @ticket = request.params['ticket']
          return fail!(:no_ticket, MissingCASTicket.new('No CAS Ticket')) unless @ticket
          fetch_raw_info(@ticket)
          return fail!(:invalid_ticket, InvalidCASTicket.new('Invalid CAS Ticket')) if raw_info.empty?
          super
        end
      end

      def request_phase
        service_url = append_params(callback_url, return_url)

        if validate_service_url!(service_url)
          [
            302,
            {
              'Location' => login_url(service_url),
              'Content-Type' => 'text/plain'
            },
            ["You are being redirected to CAS for sign-in."]
          ]
        else
          [ 400, {}, [ "Bad request" ] ]
        end
      end

      def on_sso_path?
        request.post? && request.params.has_key?('logoutRequest')
      end

      def single_sign_out_phase
        logout_request_service.new(self, request).call(options)
      end

      # Build a CAS host with protocol and port
      #
      #
      def cas_url
        extract_url if options['url']
        validate_cas_setup

        by_host_cas_url || static_cas_url
      end

      def by_host_cas_url
        return unless options.url_by_request_host && \
          options.url_by_request_host.respond_to?(:fetch)

        uri = options.url_by_request_host.fetch(request.host)

        Addressable::URI.parse(uri).to_s
      rescue
        nil # When request.host is not defined or it raises,
            # or when Addressable raises, we can only resort
            # to the default.
      end

      def static_cas_url
        uri = Addressable::URI.new
        uri.host = options.host
        uri.scheme = options.ssl ? 'https' : 'http'
        uri.port = options.port
        uri.path = options.path
        uri.to_s
      end

      def extract_url
        url = Addressable::URI.parse(options.delete('url'))
        options.merge!(
          'host' => url.host,
          'port' => url.port,
          'path' => url.path,
          'ssl' => url.scheme == 'https'
        )
      end

      def validate_cas_setup
        if options.host.nil? || options.login_url.nil?
          raise ArgumentError.new(":host and :login_url MUST be provided")
        end
      end

      # Checks that the callback URL is within the scope of the target
      # service url, to protect against redirects to phishing pages.
      #
      def validate_service_url!(service_url)
        service_url = Addressable::URI.parse(service_url)

        return_url = service_url.query_values['url']

        if return_url.nil? || return_url.empty?
          fail!(:missing_return_url, MissingReturnURL.new('Missing Return URL'))
          return false
        end

        return_url = Addressable::URI.parse(return_url)

        # Check that the return URL host, if present, is equal to the service
        # URL host. If the return_url host is nil, it means this is a relative
        # url - and we can accept it.
        #
        if !return_url.host.nil? && (return_url.host != service_url.host)
          fail!(:invalid_return_url, InvalidReturnURL.new('Invalid Return URL'))
          return false
        end

        return true
      end

      # Build a service-validation URL from +service+ and +ticket+.
      # If +service+ has a ticket param, first remove it. URL-encode
      # +service+ and add it and the +ticket+ as paraemters to the
      # CAS serviceValidate URL.
      #
      # @param [String] service the service (a.k.a. return-to) URL
      # @param [String] ticket the ticket to validate
      #
      # @return [String] a URL like `http://cas.mycompany.com/serviceValidate?service=...&ticket=...`
      def service_validate_url(service_url, ticket)
        service_url = Addressable::URI.parse(service_url)
        service_url.query_values = service_url.query_values.tap { |qs| qs.delete('ticket') }
        cas_url + append_params(options.service_validate_url, {
          service: service_url.to_s,
          ticket: ticket
        })
      end

      # Build a CAS login URL from +service+.
      #
      # @param [String] service the service (a.k.a. return-to) URL
      #
      # @return [String] a URL like `http://cas.mycompany.com/login?service=...`
      def login_url(service)
        cas_url + append_params(options.login_url, { service: service })
      end

      # Adds URL-escaped +parameters+ to +base+.
      #
      # @param [String] base the base URL
      # @param [String] params the parameters to append to the URL
      #
      # @return [String] the new joined URL.
      def append_params(base, params)
        params = params.each { |k,v| v = Rack::Utils.escape(v) }
        Addressable::URI.parse(base).tap do |base_uri|
          base_uri.query_values = (base_uri.query_values || {}).merge(params)
        end.to_s
      end

      # Validate the Service Ticket
      # @return [Object] the validated Service Ticket
      def validate_service_ticket(ticket)
        ServiceTicketValidator.new(self, options, callback_url, ticket).call
      end

    private

      def fetch_raw_info(ticket)
        ticket_user_info = validate_service_ticket(ticket).user_info
        custom_user_info = options.fetch_raw_info.call(self, options, ticket, ticket_user_info)
        self.raw_info = ticket_user_info.merge(custom_user_info)
      end

      # Deletes Hash pairs with `nil` values.
      # From https://github.com/mkdynamic/omniauth-facebook/blob/972ed5e3456bcaed7df1f55efd7c05c216c8f48e/lib/omniauth/strategies/facebook.rb#L122-127
      def prune!(hash)
        hash.delete_if do |_, value|
          prune!(value) if value.is_a?(Hash)
          value.nil? || (value.respond_to?(:empty?) && value.empty?)
        end
      end

      def return_url
        # If the request already has a `url` parameter, then it will already be appended to the callback URL.
        if request.params && request.params['url']
          {}
        else
          { url: request.referer }
        end
      end

      def logout_request_service
        LogoutRequest
      end
    end
  end
end

OmniAuth.config.add_camelization 'cas', 'CAS'
