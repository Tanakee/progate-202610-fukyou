import SwiftUI

/// メールとパスワードで新規登録またはログインする
struct LoginView: View {
    @Environment(AuthStore.self) private var auth
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Picker("", selection: $isSignUp) {
                    Text("ログイン").tag(false)
                    Text("新規登録").tag(true)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }
            Section {
                TextField("メールアドレス", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("パスワード（8文字以上）", text: $password)
                    .textContentType(isSignUp ? .newPassword : .password)
            } footer: {
                Text("推しの曲を風船で飛ばすには、ログインが必要です。")
            }
            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            Section {
                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        Spacer()
                        if isSending { ProgressView() } else { Text(isSignUp ? "登録する" : "ログインする") }
                        Spacer()
                    }
                }
                .disabled(isSending || email.isEmpty || password.isEmpty)
            }
        }
        .navigationTitle(isSignUp ? "新規登録" : "ログイン")
        .skyBackground()
    }

    private func submit() async {
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            if isSignUp {
                try await auth.signUp(email: email, password: password)
            } else {
                try await auth.logIn(email: email, password: password)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
