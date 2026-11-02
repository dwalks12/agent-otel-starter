import SwiftUI

/// A speedometer for tokens per minute: a 240° dial, ticks, a red zone and an animated needle.
struct GaugeView: View {
    var value: Double
    var maximum: Double

    private let startAngle = 150.0   // degrees, clockwise from 3 o'clock
    private let sweep = 240.0

    private var fraction: Double { maximum > 0 ? min(max(value / maximum, 0), 1) : 0 }

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height * 1.15)
            let lineWidth = size * 0.07
            let radius = size / 2 - lineWidth

            ZStack {
                // Track
                Circle()
                    .trim(from: 0, to: sweep / 360)
                    .stroke(Theme.stroke, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(startAngle))
                    .frame(width: radius * 2, height: radius * 2)

                // Red zone: the last 15% of the scale
                Circle()
                    .trim(from: sweep / 360 * 0.85, to: sweep / 360)
                    .stroke(Theme.hot.opacity(0.35), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(startAngle))
                    .frame(width: radius * 2, height: radius * 2)

                // Value arc
                Circle()
                    .trim(from: 0, to: sweep / 360 * fraction)
                    .stroke(
                        AngularGradient(colors: [Theme.accentDeep, Theme.accent, Theme.cacheRead], center: .center,
                                        startAngle: .degrees(startAngle), endAngle: .degrees(startAngle + sweep)),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(startAngle))
                    .frame(width: radius * 2, height: radius * 2)

                ticks(radius: radius - lineWidth * 0.9)
                labels(radius: radius - lineWidth * 2.1, size: size)
                needle(length: radius - lineWidth * 1.2, size: size)

                VStack(spacing: 2) {
                    Text(Format.tokens(value))
                        .font(.system(size: size * 0.13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(fraction > 0.85 ? Theme.hot : Theme.text)
                        .contentTransition(.numericText())
                    Text("TOKENS / MIN")
                        .font(.system(size: max(10, size * 0.035), weight: .semibold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundStyle(Theme.muted)
                    Text("trailing 60 s")
                        .font(.system(size: max(10, size * 0.035)))
                        .foregroundStyle(Theme.muted)
                }
                .offset(y: size * 0.2)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .animation(.spring(response: 0.8, dampingFraction: 0.75), value: fraction)
        }
        .accessibilityElement()
        .accessibilityLabel("\(Format.tokens(value)) tokens per minute, scale to \(Format.tokens(maximum))")
    }

    private func point(angle: Double, radius: Double) -> CGPoint {
        let r = angle * .pi / 180
        return CGPoint(x: cos(r) * radius, y: sin(r) * radius)
    }

    private func ticks(radius: Double) -> some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            for i in 0...40 {
                let angle = startAngle + sweep * Double(i) / 40
                let major = i % 10 == 0
                let outer = point(angle: angle, radius: radius)
                let inner = point(angle: angle, radius: radius - (major ? 14 : 7))
                var path = Path()
                path.move(to: CGPoint(x: center.x + inner.x, y: center.y + inner.y))
                path.addLine(to: CGPoint(x: center.x + outer.x, y: center.y + outer.y))
                context.stroke(path, with: .color(major ? Theme.body : Theme.muted.opacity(0.6)), lineWidth: major ? 2 : 1)
            }
        }
    }

    private func labels(radius: Double, size: Double) -> some View {
        ZStack {
            ForEach(0..<5) { i in
                let p = point(angle: startAngle + sweep * Double(i) / 4, radius: radius)
                Text(Format.tokens(maximum * Double(i) / 4))
                    .font(.system(size: max(10, size * 0.035), design: .monospaced))
                    .foregroundStyle(Theme.muted)
                    .offset(x: p.x, y: p.y)
            }
        }
    }

    private func needle(length: Double, size: Double) -> some View {
        ZStack {
            Capsule()
                .fill(Theme.text)
                .frame(width: length, height: max(3, size * 0.012))
                .offset(x: length / 2)
                .rotationEffect(.degrees(startAngle + sweep * fraction))
            Circle()
                .fill(Theme.background)
                .overlay(Circle().stroke(Theme.text, lineWidth: max(2, size * 0.01)))
                .frame(width: size * 0.07, height: size * 0.07)
        }
    }
}

/// The trailing-60-second token mix as one stacked bar with a legend.
struct TokenMixBar: View {
    var usage: Usage

    private var parts: [(String, Double?, Color)] {
        [("Cache read", usage.cacheRead, Theme.cacheRead), ("Cache write", usage.cacheWrite, Theme.cacheWrite),
         ("Fresh input", usage.input, Theme.freshInput), ("Output", usage.output, Theme.output)]
    }

    var body: some View {
        let total = usage.totalTokens
        VStack(alignment: .leading, spacing: 10) {
            Text("MIX RIGHT NOW").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.5).foregroundStyle(Theme.muted)
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    if let total, total > 0 {
                        ForEach(parts, id: \.0) { part in
                            Rectangle().fill(part.2)
                                .frame(width: max(0, proxy.size.width * (part.1 ?? 0) / total - 2))
                        }
                    } else {
                        Rectangle().fill(Theme.stroke)
                    }
                }
            }
            .frame(height: 10)
            .clipShape(Capsule())

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                ForEach(parts, id: \.0) { part in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2).fill(part.2).frame(width: 9, height: 9)
                        Text(part.0).foregroundStyle(Theme.body)
                        Text(Format.percent(part.1, of: total)).foregroundStyle(Theme.text).monospacedDigit()
                    }
                    .font(.system(size: 12))
                }
            }
        }
    }
}
