class AuthToken < ApplicationRecord
  belongs_to :user

  attr_reader :token

  before_create do
    @token = SecureRandom.urlsafe_base64(32)
    self.token_digest = self.class.digest(token)
  end

  def self.find_by_token(token)
    find_by(token_digest: digest(token))
  end

  # パスワードと違って argon2 にしないのは、token が推測できないほど長いランダムな値だから
  def self.digest(token)
    OpenSSL::Digest::SHA256.hexdigest(token)
  end
end
