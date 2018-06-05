require 'securerandom'

module ASpaceMappings
  module MARC21

    def self.get_marc_source_code(code)

      marc_code = case code
                  when 'naf', 'lcsh', 'lcnaf', 'Library of Congress Subject Headings'; 0
                  when 'lcshac'; 1
                  when 'mesh'; 2
                  when 'nal'; 3
                  when nil; 4
                  when 'cash'; 5
                  when 'rvm'; 6
                  else; 7
                  end

      marc_code.to_s
    end
  end
end
