import SwiftUI

struct FobRealityViewWrapper: UIViewRepresentable {
    var onTap: () -> Void
    var onLongPress: () -> Void
    
    func makeUIView(context: Context) -> FobRealityView {
        let view = FobRealityView(
            onTap: onTap,
            onLongPress: onLongPress
        )
        return view
    }
    
    func updateUIView(_ uiView: FobRealityView, context: Context) {
        // No dynamic updates needed for now
    }
}
