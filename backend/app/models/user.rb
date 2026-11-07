class User < ApplicationRecord
  # 利用者がいないときに照合を省くと、応答の速さで登録済みのメールアドレスを見分けられてしまう
  DUMMY_PASSWORD_DIGEST = Argon2::Password.create(SecureRandom.hex(16))

  has_many :auth_tokens, dependent: :delete_all

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }, uniqueness: true
  validates :password, length: { in: 8..128 }, on: :create

  attr_reader :password

  def self.authenticate_by(attributes)
    user = find_by(email: attributes[:email])
    user if Argon2::Password.verify_password(attributes[:password].to_s, user&.password_digest || DUMMY_PASSWORD_DIGEST)
  end

  # has_secure_password（bcrypt）ではなく argon2 を使う。チームの方針
  def password=(password)
    @password = password
    self.password_digest = Argon2::Password.create(password) if password.present?
  end
end
