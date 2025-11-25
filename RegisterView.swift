//
//  RegisterView.swift
//  DSD
//
//  Created by Dynasty Stat Drop on 7/8/25.
//  BIG FUCKING LOGO AT THE TOP CENTER
//

import SwiftUI

struct RegisterView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) var dismiss
    @State private var email = ""
    @State private var username = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showPassword = false
    @State private var showConfirmPassword = false
    @State private var isLoading = false
    @FocusState private var focusedField: FormField?

    // MARK: - Body
    var body: some View {
        NavigationStack {
            ZStack {
                // Original background image
                Image("Background1")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()

                content
                    .padding(.horizontal, 24)
            }
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .foregroundColor(.orange)
                            .font(.title2)
                            .bold()
                    }
                }
                // NO NAVIGATION TITLE - LET THE BIG LOGO BREATHE
            }
        }
        .alert("Registration Error", isPresented: $authViewModel.showError) {
            Button("OK") { authViewModel.showError = false }
        } message: {
            Text(authViewModel.errorMessage)
        }
        .onChange(of: authViewModel.registrationCompleted) { _, newValue in
            if newValue {
                dismiss()
                authViewModel.registrationCompleted = false
            }
        }
    }

    // MARK: - Content
    private var content: some View {
        ScrollView {
            VStack(spacing: 40) {
                // Header Section - BIG FUCKING LOGO
                headerSection
                
                // Form Section (Username first, then Email, then Passwords)
                formSection
                
                // Action Section
                actionSection
                
                Spacer(minLength: 100)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                focusedField = .username
            }
        }
    }

    // MARK: - Header Section - BIG FUCKING LOGO
    private var headerSection: some View {
        VStack(spacing: 24) {
            // BIG FUCKING LOGO - CENTERED AT TOP
            Image("DynastyStatDropLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 160) // BIG ASS LOGO
                .frame(maxWidth: .infinity) // Full width
                .padding(.top, 30) // Space from top safe area
                .padding(.bottom, 20) // Space below logo
            
            Text("Join Dynasty Stat Drop")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.orange)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
            
            Text("Create your account to track your dynasty leagues")
                .font(.body)
                .foregroundColor(.orange.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
    }

    // MARK: - Form Section (Username first, then Email, then Passwords)
    private var formSection: some View {
        VStack(spacing: 32) {
            // Username Field
            VStack(alignment: .leading, spacing: 8) {
                Text("UserName:")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.orange)
                
                LegacyTextField(
                    placeholder: "Enter your username",
                    text: $username,
                    keyboardType: .default,
                    focusedField: $focusedField,
                    field: .username,
                    nextField: .email,
                    isSecure: false
                )
            }
            
            // Email Field
            VStack(alignment: .leading, spacing: 8) {
                Text("Email:")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.orange)
                
                LegacyTextField(
                    placeholder: "Enter your email address",
                    text: $email,
                    keyboardType: .emailAddress,
                    focusedField: $focusedField,
                    field: .email,
                    nextField: .password,
                    isSecure: false
                )
            }
            
            // Password Field
            VStack(alignment: .leading, spacing: 8) {
                Text("Password:")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.orange)
                
                LegacySecureField(
                    placeholder: "Enter password",
                    text: $password,
                    showPassword: $showPassword,
                    focusedField: $focusedField,
                    field: .password,
                    nextField: .confirmPassword,
                    isSecure: true
                )
            }
            
            // Confirm Password Field
            VStack(alignment: .leading, spacing: 8) {
                Text("Confirm Password:")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.orange)
                
                LegacySecureField(
                    placeholder: "Confirm password",
                    text: $confirmPassword,
                    showPassword: $showConfirmPassword,
                    focusedField: $focusedField,
                    field: .confirmPassword,
                    nextField: nil,
                    isSecure: true
                )
            }
        }
        .adaptiveWidth(max: 400)
    }

    // MARK: - Action Section
    private var actionSection: some View {
        VStack(spacing: 24) {
            // Original button style with modern sizing
            Button(action: register) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                            .scaleEffect(0.8)
                    }
                    
                    Text(isLoading ? "Creating Account..." : "Register")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                .frame(width: 180, height: 48)
                .background(
                    Image("Button")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                )
                .foregroundColor(.orange)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(isLoading || !isFormValid)
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Divider with text
            HStack {
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(.orange.opacity(0.3))
                
                Text("or")
                    .font(.caption)
                    .foregroundColor(.orange.opacity(0.6))
                
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(.orange.opacity(0.3))
            }
            .padding(.horizontal, 20)
            
            // Login link
            Button(action: {
                dismiss()
            }) {
                Text("Already have an account? Sign In")
                    .font(.footnote)
                    .foregroundColor(.orange.opacity(0.8))
            }
        }
        .adaptiveWidth(max: 300)
    }

    // MARK: - Form Validation
    private var isFormValid: Bool {
        !email.isEmpty &&
        !username.isEmpty &&
        !password.isEmpty &&
        !confirmPassword.isEmpty &&
        isValidEmail(email) &&
        password.count >= 8 &&
        password == confirmPassword
    }

    // MARK: - Actions
    private func register() {
        guard isFormValid else {
            showValidationError()
            return
        }
        
        isLoading = true
        focusedField = nil
        
        UserDefaults.standard.set(email, forKey: "registeredEmail")
        UserDefaults.standard.set(username, forKey: "registeredUsername")
        UserDefaults.standard.set(password, forKey: "registeredPassword")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            authViewModel.registrationCompleted = true
            isLoading = false
        }
    }
    
    private func showValidationError() {
        if email.isEmpty || username.isEmpty || password.isEmpty || confirmPassword.isEmpty {
            authViewModel.errorMessage = "Please fill in all fields"
        } else if !isValidEmail(email) {
            authViewModel.errorMessage = "Please enter a valid email address"
        } else if password.count < 8 {
            authViewModel.errorMessage = "Password must be at least 8 characters long"
        } else if password != confirmPassword {
            authViewModel.errorMessage = "Passwords do not match"
        }
        authViewModel.showError = true
    }

    private func isValidEmail(_ email: String) -> Bool {
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        return NSPredicate(format: "SELF MATCHES %@", emailRegEx).evaluate(with: email)
    }

    // MARK: - Field Identifiers (Updated order)
    enum FormField: Hashable {
        case username, email, password, confirmPassword
    }
}

// MARK: - Legacy Text Field (Original Visual Style)
struct LegacyTextField: View {
    let placeholder: String
    @Binding var text: String
    let keyboardType: UIKeyboardType
    @FocusState.Binding var focusedField: RegisterView.FormField?
    let field: RegisterView.FormField
    let nextField: RegisterView.FormField?
    let isSecure: Bool
    
    var body: some View {
        ZStack(alignment: .leading) {
            Image("TextBar")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .allowsHitTesting(false)
            
            Group {
                if isSecure {
                    SecureField("", text: $text)
                        .textContentType(.password)
                } else {
                    TextField("", text: $text)
                        .textInputAutocapitalization(.never)
                        .keyboardType(keyboardType)
                        .autocorrectionDisabled(true)
                }
            }
            .padding(.horizontal, 75)
            .foregroundColor(.red)
            .focused($focusedField, equals: field)
            .submitLabel(nextField != nil ? .next : .done)
            .onSubmit {
                if let next = nextField {
                    focusedField = next
                }
            }
            .textFieldStyle(.plain)
            .onTapGesture {
                focusedField = field
            }
            
            if text.isEmpty {
                Text(placeholder)
                    .foregroundColor(.orange)
                    .padding(.leading, 75)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(height: 50)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    focusedField == field ?
                    Color.orange :
                    Color.clear,
                    lineWidth: 2
                )
        )
    }
}

// MARK: - Legacy Secure Field (Original Visual Style with Toggle)
struct LegacySecureField: View {
    let placeholder: String
    @Binding var text: String
    @Binding var showPassword: Bool
    @FocusState.Binding var focusedField: RegisterView.FormField?
    let field: RegisterView.FormField
    let nextField: RegisterView.FormField?
    let isSecure: Bool
    
    var body: some View {
        HStack(spacing: 0) {
            LegacyTextField(
                placeholder: placeholder,
                text: $text,
                keyboardType: .default,
                focusedField: $focusedField,
                field: field,
                nextField: nextField,
                isSecure: !showPassword
            )
            
            Button(action: { showPassword.toggle() }) {
                Image(systemName: showPassword ? "eye.slash" : "eye")
                    .foregroundColor(.orange)
                    .font(.caption)
                    .padding(.trailing, 8)
            }
            .frame(width: 40, height: 50)
            .background(Color.clear)
        }
        .frame(height: 50)
    }
}

// MARK: - View Extensions
extension View {
    func adaptiveLogo(max: CGFloat) -> some View {
        self.frame(maxWidth: max, maxHeight: max)
    }
    
    func adaptiveWidth(max: CGFloat) -> some View {
        self.frame(maxWidth: max)
    }
}

// MARK: - Preview
#Preview {
    RegisterView()
        .environmentObject(AuthViewModel())
}
