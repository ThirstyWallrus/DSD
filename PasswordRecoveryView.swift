//
//  PasswordRecoveryView.swift
//  DSD
//
//  Created by Dynasty Stat Drop on 7/8/25.
//


import SwiftUI

struct PasswordRecoveryView: View {
    @State private var email = ""
    @State private var isRecoverySent = false

    var body: some View {
        ZStack {
            Image("Background1")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Text("Password Recovery")
                    .font(.largeTitle)
                    .foregroundColor(.orange)

                ZStack(alignment: .leading) {
                    Image("UsernameBar")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .padding()

                    if email.isEmpty {
                        Text("Email:")
                            .foregroundColor(.orange)
                            .padding(.leading, 75)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    TextField("", text: $email)
                        .padding(.horizontal, 75)
                        .background(Color.clear)
                        .foregroundColor(.red)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                }
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)

                Button {
                    print("Recovery email sent to: \(email)")
                    isRecoverySent = true
                } label: {
                    Image("Button")
                        .resizable()
                        .frame(width: 150, height: 40)
                        .overlay(
                            Text("Send Recovery Email")
                                .foregroundColor(.orange)
                                .font(.headline)
                        )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            }
            .alert(isPresented: $isRecoverySent) {
                Alert(
                    title: Text("Recovery Sent"),
                    message: Text("A recovery email has been sent to \(email). Check your inbox."),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }
}

#Preview("PasswordRecovery Preview") {
    PasswordRecoveryView()
}