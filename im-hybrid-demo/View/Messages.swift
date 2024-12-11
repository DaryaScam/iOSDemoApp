//
//  Messages.swift
//  im-hybrid-demo
//
//  Created by Yuriy Ackermann <ackermann.yuriy@gmail.com> <@yackermann>
//  As a part of DaryaScam Project <https://daryascam.info>
//

import SwiftUI


func ChatBox(name: String, message: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
        Image(systemName: "person.circle.fill")
            .resizable()
            .frame(width: 64, height: 64)
            .foregroundColor(.gray)
        
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.title3)
                .fontWeight(.semibold)
            
            Text(message)
                .font(.body)
                .foregroundColor(.gray)
                .lineLimit(2)
            
        }
    }
}
