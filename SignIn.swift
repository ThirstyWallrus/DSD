import SwiftUI

enum FormFieldFocus: Hashable {
    case username
    case password
}

struct SignIn: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var username = ""
    @State private var password = ""
    @State private var rememberMeLocal = false
    @State private var showingRegister = false
    @State private var navigationPath = NavigationPath()
    @FocusState private var focus: FormFieldFocus?

    let adminUsername = "admin"
    let adminPassword = "admin1234"

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                Image("Background1")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        Image("DynastyStatDropLogo")
                            .resizable()
                            .scaledToFit()
                            .adaptiveLogo(max: 420, screenFraction: 0.9)   // Uses global adaptiveLogo from AdaptiveWidthModifier.swift

                        // Username Field
                        ZStack(alignment: .leading) {
                            Image("TextBar")
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(height: 40)
                                .allowsHitTesting(false)
                            if username.isEmpty {
                                Text("Username")
                                    .foregroundColor(.white.opacity(0.7))
                                    .padding(.horizontal, 55)
                            }
                            TextField("", text: $username)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .padding(.horizontal, 55)
                                .foregroundColor(.white)
                                .focused($focus, equals: .username)
                        }
                        .frame(height: 40)
                        .padding(.horizontal)

                        // Password Field
                        ZStack(alignment: .leading) {
                            Image("TextBar")
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(height: 40)
                                .allowsHitTesting(false)
                            if password.isEmpty {
                                Text("Password")
                                    .foregroundColor(.white.opacity(0.7))
                                    .padding(.horizontal, 55)
                            }
                            SecureField("", text: $password)
                                .padding(.horizontal, 55)
                                .foregroundColor(.white)
                                .focused($focus, equals: .password)
                        }
                        .frame(height: 40)
                        .padding(.horizontal)

                        // Remember Me & Forgot Password
                        HStack {
                            Toggle(isOn: $rememberMeLocal) {
                                Text("Remember Me")
                                    .foregroundColor(.white)
                                    .font(.system(size: 16, weight: .medium))
                            }
                            .labelsHidden()
                            .accessibilityLabel("Remember Me")
                            Spacer()
                            Button {
                                navigationPath.append("passwordRecovery")
                            } label: {
                                Text("Forgot Password?")
                                    .foregroundColor(.blue)
                                    .font(.footnote)
                            }
                        }
                        .padding(.horizontal)

                        // Sign In Button
                        Button(action: handleSignIn) {
                            Image("signinButton")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 180, height: 40)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 10)

                        // Register Link
                        Button { showingRegister = true } label: {
                            Text("Don’t have an account? Register")
                                .foregroundColor(.blue)
                                .font(.footnote)
                                .frame(maxWidth: .infinity)
                        }
                        .padding(.bottom, 20)
                    }
                    .padding(.vertical)
                    .frame(maxWidth: 400)
                }
            }
            .sheet(isPresented: $showingRegister) {
                RegisterView()
            }
            .navigationDestination(for: String.self) { dest in
                if dest == "passwordRecovery" {
                    PasswordRecoveryView()
                } else {
                    EmptyView()
                }
            }
            .onAppear {
                print("SignIn instanceID:", authViewModel.instanceID)
                    print("SignIn isLoggedIn:", authViewModel.isLoggedIn)
                    print("SignIn currentUsername:", authViewModel.currentUsername)
                    preloadRememberedUsername() }
            .alert(isPresented: $authViewModel.showError) {
                Alert(title: Text("Error"),
                      message: Text(authViewModel.errorMessage),
                      dismissButton: .default(Text("OK")) {
                          authViewModel.showError = false
                      })
            }
        }
    }

    private func preloadRememberedUsername() {
        guard !authViewModel.isLoggedIn else { return }
        if let remembered = authViewModel.rememberedUsername {
            username = remembered
            rememberMeLocal = true
        }
    }

    private func handleSignIn() {
        focus = nil
        guard !username.isEmpty, !password.isEmpty else {
            authViewModel.errorMessage = "Enter UserName and Password to continue to DSD"
            authViewModel.showError = true
            return
        }
        if username == adminUsername && password == adminPassword {
            authViewModel.login(identifier: username, password: password, remember: rememberMeLocal)
        } else {
            authViewModel.signIn(username: username, password: password, remember: rememberMeLocal)
        }
    }
}

