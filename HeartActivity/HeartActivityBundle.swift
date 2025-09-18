//
//  HeartActivityBundle.swift
//  HeartActivity
//
//  Created by Egor on 19.09.2025.
//

import WidgetKit
import SwiftUI

@main
struct HeartActivityBundle: WidgetBundle {
    var body: some Widget {
        HeartActivity()
        HeartActivityControl()
        HeartActivityLiveActivity()
    }
}
