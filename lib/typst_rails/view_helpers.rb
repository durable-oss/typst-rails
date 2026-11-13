# frozen_string_literal: true

require "erb"
require "typst_rails/helpers"

module TypstRails
  # {Helpers} as mixed into ActionView, so `.typ` templates can call
  # `escape_typst`, `markdown_to_typst`, and the rest directly.
  #
  # The Railtie includes this module into ActionView::Base, which every view
  # shares, HTML views included.
  #
  # @example In app/views/reports/monthly.typ
  #   = <%= escape_typst(@title) %>
  module ViewHelpers
    include Helpers

    # ActionView::Base already includes ERB::Util#url_encode, which encodes a
    # space as "%20"; {Helpers#url_encode} would encode it as "+". Keep the
    # ActionView behavior so existing HTML views are unaffected.
    #
    # @param text [String, nil]
    # @return [String]
    def url_encode(text)
      ERB::Util.url_encode(text)
    end
  end
end
