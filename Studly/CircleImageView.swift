import SwiftUI

struct CircleImageView: View {
    var body: some View {
        Image("зелёная").resizable().frame(width: 100, height: 100).clipShape(RoundedRectangle(cornerRadius: 30))
            
    }
}

struct LogCircleImageView: View {
    var body: some View {
        Image("обычная").resizable().frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 50))
            
    }
}

#Preview {
    CircleImageView()
}


#Preview {
    LogCircleImageView()
}
