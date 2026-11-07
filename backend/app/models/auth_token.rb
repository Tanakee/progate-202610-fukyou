class AuthToken < ApplicationRecord
  belongs_to :user

  # token を発行して、平文の token を返す。DB にはハッシュだけを保存する
  def self.issue!(user)
    token = SecureRandom.urlsafe_base64(32)
    user.auth_tokens.create!(token_digest: digest(token))
    token
  end

  def self.find_by_token(token)
    find_by(token_digest: digest(token))
  end

  # token は十分に長いランダムな値なので、パスワードと違って SHA-256 で足りる
  def self.digest(token)
    OpenSSL::Digest::SHA256.hexdigest(token)
  end
  private_class_method :digest
end
