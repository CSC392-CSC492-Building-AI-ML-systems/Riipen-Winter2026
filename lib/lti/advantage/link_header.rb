# frozen_string_literal: true

require "uri"

module Lti
  module Advantage
    # Utilities for parsing RFC 8288 Link headers returned by LTI services.
    #
    # The AGS and NRPS clients use this helper to resolve pagination and other
    # relation URLs from HTTP response headers.
    module LinkHeader
      module_function

      # Returns the first URL for the requested Link relation.
      #
      # header:: Raw HTTP +Link+ header String.
      # relation:: Relation name to locate, such as <tt>"next"</tt>.
      # base_url:: Optional absolute URL used to resolve relative links.
      #
      # Returns the resolved URL String or +nil+ when the relation is absent.
      def relation_url(header, relation, base_url: nil)
        target_relation = relation.to_s.downcase

        parse_entries(header, base_url: base_url).each do |entry|
          relations = entry.fetch(:params).fetch("rel", "").split(/\s+/).reject(&:empty?)
          next unless relations.any? { |value| value.casecmp(target_relation).zero? }

          return entry.fetch(:url)
        end

        nil
      end

      # Parses a raw Link header into an Array of entries.
      #
      # header:: Raw HTTP +Link+ header String.
      # base_url:: Optional absolute URL used to resolve relative links.
      #
      # Returns an Array of Hashes containing +:url+ and +:params+ keys.
      # Raises +ArgumentError+ when the header is malformed.
      def parse_entries(header, base_url: nil)
        return [] if header.nil? || header.to_s.empty?

        entries = []
        index = 0

        while index < header.length
          index = skip_link_delimiters(header, index)
          break if index >= header.length
          raise ArgumentError, "Malformed Link header" unless header[index] == "<"

          url, index = parse_link_url(header, index)
          params, index = parse_link_params(header, index)
          entries << { url: resolve_url(url, base_url: base_url), params: params }
        end

        entries
      end

      # :nodoc:
      def skip_link_delimiters(header, index)
        index += 1 while index < header.length && [",", " ", "\t"].include?(header[index])

        index
      end
      private_class_method :skip_link_delimiters

      # :nodoc:
      def parse_link_url(header, index)
        closing_index = header.index(">", index + 1)
        raise ArgumentError, "Malformed Link header" if closing_index.nil?

        [header[(index + 1)...closing_index], closing_index + 1]
      end
      private_class_method :parse_link_url

      # :nodoc:
      def parse_link_params(header, index)
        params = {}

        loop do
          index = skip_optional_whitespace(header, index)
          break unless index < header.length && header[index] == ";"

          index += 1
          index = skip_optional_whitespace(header, index)
          name, value, index = parse_link_param(header, index)
          params[name] = value
        end

        [params, index]
      end
      private_class_method :parse_link_params

      # :nodoc:
      def skip_optional_whitespace(header, index)
        index += 1 while index < header.length && [" ", "\t"].include?(header[index])

        index
      end
      private_class_method :skip_optional_whitespace

      # :nodoc:
      def parse_link_param(header, index)
        name_start = index
        index += 1 while index < header.length && !["=", ";", ","].include?(header[index])

        name = header[name_start...index].to_s.strip.downcase
        raise ArgumentError, "Malformed Link header" if name.empty?

        return [name, "", index] unless index < header.length && header[index] == "="

        index += 1
        index = skip_optional_whitespace(header, index)
        value, index = parse_link_param_value(header, index)
        [name, value, index]
      end
      private_class_method :parse_link_param

      # :nodoc:
      def parse_link_param_value(header, index)
        return ["", index] if index >= header.length

        if ["\"", "'"].include?(header[index])
          parse_quoted_link_param_value(header, index + 1, quote_char: header[index])
        else
          value_start = index
          index += 1 while index < header.length && ![";", ","].include?(header[index])

          [header[value_start...index].to_s.strip, index]
        end
      end
      private_class_method :parse_link_param_value

      # :nodoc:
      def parse_quoted_link_param_value(header, index, quote_char:)
        value = +""

        while index < header.length
          char = header[index]
          if char == "\\"
            index += 1
            raise ArgumentError, "Malformed Link header" if index >= header.length

            value << header[index]
          elsif char == quote_char
            return [value, index + 1]
          else
            value << char
          end

          index += 1
        end

        raise ArgumentError, "Malformed Link header"
      end
      private_class_method :parse_quoted_link_param_value

      # :nodoc:
      def resolve_url(url, base_url: nil)
        stripped = url.to_s.strip
        return stripped if stripped.empty? || base_url.nil?

        URI.join(base_url, stripped).to_s
      end
      private_class_method :resolve_url
    end
  end
end
