# frozen_string_literal: true

module Lti
  module Advantage
    module Oidc
      # Handles the initial OIDC login request from the Platform (LMS).
      # This is the "start" of the handshake.
      class LoginInitiation
        attr_reader :params

        def initialize(params)
          @params = params
        end

        # Validates that we have the minimum required info from the LMS
        def validate!
          raise Error, "iss (issuer) is missing" if params[:iss].nil?
          raise Error, "login_hint is missing" if params[:login_hint].nil?
          raise Error, "target_link_uri is missing" if params[:target_link_uri].nil?
        end

        # Generates the data needed to redirect the user back to the LMS.
        # @param client_id [String] Your tool's ID in the LMS
        # @param redirect_uri [String] The URL where the LMS should send the user back to
        # @param state [String] A random string to track the request
        # @param nonce [String] A random string to prevent "replay" attacks
        def redirect_params(client_id:, redirect_uri:, state:, nonce:)
          {
            scope: "openid",
            response_type: "id_token",
            client_id: client_id,
            redirect_uri: redirect_uri,
            login_hint: params[:login_hint],
            lti_message_hint: params[:lti_message_hint],
            state: state,
            nonce: nonce,
            response_mode: "form_post"
          }.compact
        end
      end
    end
  end
end
