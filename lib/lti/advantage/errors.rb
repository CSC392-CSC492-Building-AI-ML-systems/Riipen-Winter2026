# frozen_string_literal: true

module Lti
  module Advantage
    class Error < StandardError; end
    class ConfigurationError < Error; end
    class ValidationError < Error; end
    class ReplayError < Error; end
    class JwtVerificationError < Error; end
  end
end
