class User < ApplicationRecord
  PASSWORD_LENGTH = 8..128

  has_many :auth_tokens, dependent: :delete_all

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }, uniqueness: true
  validates :password, length: { in: PASSWORD_LENGTH }, if: -> { new_record? || password_digest_changed? }

  attr_reader :password

  # メールアドレスとパスワードが合えば利用者を、合わなければ nil を返す
  def self.authenticate_by_credentials(email:, password:)
    user = find_by(email: email)
    # 利用者がいないときもハッシュの照合をして、応答時間から登録の有無を推測されないようにする
    digest = user&.password_digest || dummy_password_digest
    user if Argon2::Password.verify_password(password.to_s, digest)
  end

  def self.dummy_password_digest
    @dummy_password_digest ||= Argon2::Password.create(SecureRandom.hex(16))
  end
  private_class_method :dummy_password_digest

  # パスワードは argon2（Argon2id）でハッシュ化して保存する。平文は保存しない
  def password=(raw_password)
    @password = raw_password
    self.password_digest = raw_password.present? ? Argon2::Password.create(raw_password) : nil
  end
end
