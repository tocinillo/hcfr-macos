// HCFR for macOS
// Copyright (C) 2026 Jorge Velázquez
// AutoCAL icon, added in 2026: three overlapping red, green and blue circles mixed additively (the
// three channels a calibration balances, white where they meet).
//
// This program is free software; you can redistribute it and/or modify it under the terms of
// the GNU General Public License version 2 as published by the Free Software Foundation.
// It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
// the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See LICENSE.

import SwiftUI

struct RGBCirclesIcon: View {
    var size: CGFloat = 16

    var body: some View {
        let d = size * 0.62
        let r = size * 0.19
        ZStack {
            circle(Color(red: 1, green: 0.16, blue: 0.16), d).offset(x: 0, y: -r)
            circle(Color(red: 0.12, green: 0.86, blue: 0.24), d).offset(x: -r * 0.87, y: r * 0.5)
            circle(Color(red: 0.18, green: 0.36, blue: 1), d).offset(x: r * 0.87, y: r * 0.5)
        }
        .compositingGroup()
        .frame(width: size, height: size)
        .accessibilityLabel("AutoCAL")
    }

    private func circle(_ c: Color, _ d: CGFloat) -> some View {
        Circle().fill(c).frame(width: d, height: d).blendMode(.screen)
    }
}
