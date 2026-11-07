class Current < ActiveSupport::CurrentAttributes
  attribute :auth_token
  delegate :user, to: :auth_token, allow_nil: true
end
