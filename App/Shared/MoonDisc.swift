// App/Shared/MoonDisc.swift
//
// The Moon's lit shape, shared by the app and its widgets.

import SwiftUI

/// The Moon as seen by the observer: lit part for a given elongation (0 new, 180 full),
/// mirrored for the southern hemisphere.
struct MoonDisc: View {
    let elongation: Double
    let southern: Bool

    var body: some View {
        ZStack {
            Circle().fill(Color(white: 0.18))
            MoonLitShape(elongation: elongation, mirrored: southern)
                .fill(Color(white: 0.93))
            Circle().strokeBorder(Color.secondary.opacity(0.4), lineWidth: 0.5)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

struct MoonLitShape: Shape {
    let elongation: Double
    let mirrored: Bool

    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var e = elongation.truncatingRemainder(dividingBy: 360)
        if e < 0 { e += 360 }
        // Waxing (0–180°): right limb lit as seen from the north; waning: left limb.
        let waning = e > 180
        let a = waning ? 360 - e : e
        let flip: CGFloat = (waning != mirrored) ? -1 : 1
        let k = CGFloat(cos(a * .pi / 180))
        let steps = 48
        var path = Path()
        // Lit limb: top → bottom around the lit side.
        for i in 0...steps {
            let theta = -CGFloat.pi / 2 + CGFloat.pi * CGFloat(i) / CGFloat(steps)
            let p = CGPoint(x: center.x + flip * r * cos(theta), y: center.y + r * sin(theta))
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        // Terminator: bottom → top, half-ellipse with x-radius r·cos(a).
        for i in 0...steps {
            let theta = CGFloat.pi / 2 - CGFloat.pi * CGFloat(i) / CGFloat(steps)
            path.addLine(to: CGPoint(x: center.x + flip * k * r * cos(theta), y: center.y + r * sin(theta)))
        }
        path.closeSubpath()
        return path
    }
}
