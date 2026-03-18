//
//  OverlayView.swift
//  CopyThat
//

import SwiftUI

struct OverlayView: View {
    var line1: String?
    var line2: String?
    
    var body: some View {
        HStack {
            
            HStack {
                Image("MessageBubble").foregroundColor(.white)
                VStack(alignment: .leading) {
                    if let line1 = line1 {
                        Text(line1).font(.system(size: 18)).foregroundColor(.white)
                    }
                    if let line2 = line2 {
                        Text(line2).foregroundColor(.white)
                    }
                }
            }
            .padding(8)
            .background(Color(red: 0.0, green: 0.48, blue: 1.0))
            .cornerRadius(12)
        }
        .padding(8)
        .cornerRadius(5)
    }
}

struct OverlayView_Previews: PreviewProvider {
    static var previews: some View {
        OverlayView(line1: "Line 1", line2: "Sub text")
    }
}
