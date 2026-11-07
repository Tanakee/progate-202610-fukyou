class User < ApplicationRecord
  has_many :auth_tokens, dependent: :delete_all

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }, uniqueness: true
  validates :password, length: { in: 8..128 }, if: -> { new_record? || password_digest_changed? }

  attr_reader :password

  def self.authenticate_by(attributes)
    user = find_by(email: attributes[:email])
    # 利用者がいないときに照合を省くと、応答の速さで登録済みのメールアドレスを見分けられてしまう
    digest = user&.password_digest || dummy_password_digest
    user if Argon2::Password.verify_password(attributes[:password].to_s, digest)
  end

  def self.dummy_password_digest
    @dummy_password_digest ||= Argon2::Password.create(SecureRandom.hex(16))
  end
  private_class_method :dummy_password_digest

  # has_secure_password（bcrypt）ではなく argon2 を使う。チームの方針
  def password=(password)
    @password = password
    self.password_digest = password.present? ? Argon2::Password.create(password) : nil
  end
end
