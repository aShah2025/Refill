import SwiftUI

struct TeacherHomeView: View {
    @State private var textInput = ""
    @State private var isRecording = false
    
    let placeholderTextDefault = "Type or speak your classroom need in plain English (e.g., 'I need 25 math 
textbooks urgently')."
    let placeholderTextListening = "Listening... Speak your need now!"
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("What does your classroom need?")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.top)
            
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .shadow(radius: 4)
                
                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: $textInput)
                        .font(.body)
                        .foregroundColor(textInput.isEmpty ? Color.gray : Color.black)
                        .placeholder(when: textInput.isEmpty) {
                            Text(isRecording ? placeholderTextListening : placeholderTextDefault)
                                .foregroundColor(Color.gray)
                        }
                        .padding()
                    
                    if isRecording {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .red))
                            .frame(width: 50, height: 50)
                    }
                }
            }
            
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isRecording.toggle()
                    textInput = isRecording ? "" : placeholderTextDefault
                }
            }) {
                ZStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 70, height: 70)
                        .scaleEffect(isRecording ? 1.2 : 1.0)
                        .animation(Animation.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value:
isRecording)
                    
                    Image(systemName: "mic.fill")
                        .font(.title)
                        .foregroundColor(Color.white)
                }
            }
            
            Button(action: {
                // Handle Find Funding Match action
            }) {
                Text("Find Funding Match")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .cornerRadius(10)
            }
        }
        .padding()
    }
}

// Placeholder extension for TextEditor
extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

struct TeacherHomeView_Previews: PreviewProvider {
    static var previews: some View {
        TeacherHomeView()
    }
}

