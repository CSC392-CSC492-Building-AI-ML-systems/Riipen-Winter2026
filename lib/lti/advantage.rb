# frozen_string_literal: true

require "jwt"
require "faraday"
require_relative "advantage/version"
require_relative "advantage/oidc/login_initiation"
require_relative "advantage/message"
require_relative "advantage/key_store"
require_relative "advantage/key_pair"

module Lti
  module Advantage
    class Error < StandardError; end
    # Your code goes here...
  end
end
