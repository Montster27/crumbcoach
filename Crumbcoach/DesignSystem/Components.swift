import SwiftUI

// CrumbCoach design system primitives — Card, Kicker, StatusPill, Bar,
// RingProgress, Sparkline, TagPill, ButtonStyles, Icon helpers.

// MARK: - Kicker (uppercase tracking-wide label)

struct Kicker: View {
    let text: String
    var color: Color = Theme.slate500
    var size: CGFloat = 11
    init(_ text: String, color: Color = Theme.slate500, size: CGFloat = 11) {
        self.text = text
        self.color = color
        self.size = size
    }
    var body: some View {
        Text(text.uppercased())
            .font(Typography.ui(size, weight: .semibold))
            .kerning(1.3)
            .foregroundStyle(color)
    }
}

// MARK: - Status pill

enum PillKind {
    case good, warn, info, bad, neutral, accent
    var bg: Color {
        switch self {
        case .good:    return Theme.pillGoodBg
        case .warn:    return Theme.pillWarnBg
        case .info:    return Theme.pillInfoBg
        case .bad:     return Theme.pillBadBg
        case .neutral: return Theme.pillNeutBg
        case .accent:  return Theme.primaryTint
        }
    }
    var fg: Color {
        switch self {
        case .good:    return Theme.pillGoodFg
        case .warn:    return Theme.pillWarnFg
        case .info:    return Theme.pillInfoFg
        case .bad:     return Theme.pillBadFg
        case .neutral: return Theme.pillNeutFg
        case .accent:  return Theme.primaryDeep
        }
    }
}

struct StatusPill: View {
    let kind: PillKind
    let text: String
    var dot: Bool = false
    var body: some View {
        HStack(spacing: 5) {
            if dot {
                Circle()
                    .fill(kind.fg)
                    .frame(width: 6, height: 6)
                    .opacity(0.85)
            }
            Text(text)
                .font(Typography.ui(11, weight: .semibold))
                .kerning(0.2)
                .foregroundStyle(kind.fg)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(kind.bg, in: Capsule())
    }
}

// MARK: - Card

struct SurfaceCard<Content: View>: View {
    var padding: EdgeInsets = EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20)
    var hover: Bool = false
    var background: Color = Theme.cardBg
    @ViewBuilder var content: () -> Content

    init(padding: EdgeInsets = EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20),
         hover: Bool = false,
         background: Color = Theme.cardBg,
         @ViewBuilder content: @escaping () -> Content) {
        self.padding = padding
        self.hover = hover
        self.background = background
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .background(background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.border1, lineWidth: 1)
            )
            .shadow(color: Theme.shadowCard, radius: 1, x: 0, y: 1)
    }
}

// MARK: - Bar (progress)

struct BarView: View {
    let value: Double      // 0...1
    var color: Color = Theme.primary
    var height: CGFloat = 6
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Theme.slate200)
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(color)
                    .frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Ring progress

struct RingProgress<Center: View>: View {
    let value: Double  // 0...1
    var size: CGFloat = 64
    var stroke: CGFloat = 6
    var color: Color = Theme.primary
    var trackColor: Color = Theme.slate200
    @ViewBuilder var center: () -> Center

    var body: some View {
        ZStack {
            Circle()
                .stroke(trackColor, lineWidth: stroke)
            Circle()
                .trim(from: 0, to: max(0, min(1, value)))
                .stroke(color, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: value)
            center()
        }
        .frame(width: size, height: size)
    }
}

extension RingProgress where Center == EmptyView {
    init(value: Double, size: CGFloat = 64, stroke: CGFloat = 6,
         color: Color = Theme.primary, trackColor: Color = Theme.slate200) {
        self.value = value
        self.size = size
        self.stroke = stroke
        self.color = color
        self.trackColor = trackColor
        self.center = { EmptyView() }
    }
}

// MARK: - Sparkline

struct Sparkline: View {
    let values: [Double]
    var color: Color = Theme.primary
    var fill: Bool = true

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let pts = points(in: CGSize(width: w, height: h))
            ZStack {
                if fill {
                    Path { p in
                        guard let first = pts.first else { return }
                        p.move(to: first)
                        for pt in pts.dropFirst() { p.addLine(to: pt) }
                        p.addLine(to: CGPoint(x: w, y: h))
                        p.addLine(to: CGPoint(x: 0, y: h))
                        p.closeSubpath()
                    }
                    .fill(color.opacity(0.12))
                }
                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: first)
                    for pt in pts.dropFirst() { p.addLine(to: pt) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let mn = values.min() ?? 0
        let mx = values.max() ?? 1
        let range = max(mx - mn, 1)
        return values.enumerated().map { (i, v) in
            let x = CGFloat(i) / CGFloat(values.count - 1) * size.width
            let y = size.height - CGFloat((v - mn) / range) * (size.height - 4) - 2
            return CGPoint(x: x, y: y)
        }
    }
}

// MARK: - Tag pill (filter chip)

struct TagPill: View {
    let label: String
    var active: Bool = false
    var action: () -> Void = {}
    var body: some View {
        Button(action: {
            Haptics.select()
            action()
        }) {
            Text(label)
                .font(Typography.ui(12, weight: .medium))
                .foregroundStyle(active ? Color.white : Theme.slate700)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(active ? Theme.primary : Theme.slate100)
                .overlay(
                    Capsule().stroke(active ? Theme.primary : Theme.border1, lineWidth: 1)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Button styles

struct CCButtonStyle: ButtonStyle {
    enum Variant { case primary, secondary, ghost, icon }
    var variant: Variant = .primary
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let pad: EdgeInsets = compact
            ? EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
            : EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
        return configuration.label
            .font(Typography.ui(14, weight: .medium))
            .padding(pad)
            .background(background(configuration: configuration))
            .foregroundStyle(foreground)
            .overlay(border)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }

    private var foreground: Color {
        switch variant {
        case .primary:   return .white
        case .secondary: return Theme.slate700
        case .ghost:     return Theme.slate600
        case .icon:      return Theme.slate600
        }
    }

    @ViewBuilder private func background(configuration: Configuration) -> some View {
        switch variant {
        case .primary:   Theme.primary
        case .secondary: Theme.slate100
        case .ghost:     Color.clear
        case .icon:      Theme.cardBg
        }
    }

    @ViewBuilder private var border: some View {
        let stroke: Color = {
            switch variant {
            case .primary, .ghost: return .clear
            case .secondary, .icon: return Theme.border1
            }
        }()
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(stroke, lineWidth: 1)
    }
}

extension View {
    func ccPrimary(compact: Bool = false) -> some View {
        buttonStyle(CCButtonStyle(variant: .primary, compact: compact))
    }
    func ccSecondary(compact: Bool = false) -> some View {
        buttonStyle(CCButtonStyle(variant: .secondary, compact: compact))
    }
    func ccGhost(compact: Bool = false) -> some View {
        buttonStyle(CCButtonStyle(variant: .ghost, compact: compact))
    }
}

// MARK: - Mono / numeric Text helper

extension Text {
    func num(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> Text {
        self.font(Typography.mono(size, weight: weight))
    }
}

// MARK: - Bread photo placeholder (gradient fallback)

enum BreadKind { case crumb, crust, starter }

struct BreadPhoto: View {
    let assetName: String?
    var kind: BreadKind = .crumb
    var height: CGFloat = 160

    var body: some View {
        ZStack {
            if let n = assetName, let disk = PersistenceController.shared.loadPhoto(named: n) {
                Image(uiImage: disk)
                    .resizable()
                    .scaledToFill()
            } else if let n = assetName, UIImage(named: n) != nil {
                Image(n)
                    .resizable()
                    .scaledToFill()
            } else {
                gradient
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    @ViewBuilder private var gradient: some View {
        switch kind {
        case .crumb:
            LinearGradient(
                colors: [Color(hex: 0xD4A373), Color(hex: 0xA47148), Color(hex: 0x6B4226)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .overlay(crumbHoles)
        case .crust:
            RadialGradient(
                colors: [Color(hex: 0x6B3A14), Color(hex: 0xA05D2A), Color(hex: 0xD4A373)],
                center: .center, startRadius: 10, endRadius: 220
            )
        case .starter:
            LinearGradient(
                colors: [Color(hex: 0xF2E8D5), Color(hex: 0xD4B896), Color(hex: 0xA47D56)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .overlay(starterBubbles)
        }
    }

    private var crumbHoles: some View {
        GeometryReader { geo in
            ZStack {
                Circle().fill(.white.opacity(0.40)).frame(width: 16).position(x: geo.size.width * 0.30, y: geo.size.height * 0.30)
                Circle().fill(.white.opacity(0.30)).frame(width: 24).position(x: geo.size.width * 0.65, y: geo.size.height * 0.50)
                Circle().fill(.white.opacity(0.35)).frame(width: 12).position(x: geo.size.width * 0.25, y: geo.size.height * 0.70)
                Circle().fill(.white.opacity(0.30)).frame(width: 20).position(x: geo.size.width * 0.80, y: geo.size.height * 0.75)
            }
        }
    }

    private var starterBubbles: some View {
        GeometryReader { geo in
            ZStack {
                Circle().fill(.white.opacity(0.50)).frame(width: 8).position(x: geo.size.width * 0.40, y: geo.size.height * 0.40)
                Circle().fill(.white.opacity(0.40)).frame(width: 12).position(x: geo.size.width * 0.70, y: geo.size.height * 0.60)
                Circle().fill(.white.opacity(0.35)).frame(width: 6).position(x: geo.size.width * 0.20, y: geo.size.height * 0.55)
            }
        }
    }
}

// MARK: - Icon convenience (SF Symbols mapping)
// The design uses custom inline SVGs. We map each to the closest SF Symbol.

enum CCIcon: String {
    case home   = "house"
    case play   = "play.fill"
    case pause  = "pause.fill"
    case book   = "book"
    case clock  = "clock"
    case jar    = "cylinder"
    case starter = "drop.triangle"
    case camera = "camera"
    case graph  = "chart.line.uptrend.xyaxis"
    case device = "iphone"
    case check  = "checkmark"
    case plus   = "plus"
    case search = "magnifyingglass"
    case more   = "ellipsis"
    case filter = "line.3.horizontal.decrease"
    case thumbsUp = "hand.thumbsup"
    case thumbsDown = "hand.thumbsdown"
    case arrowRight = "arrow.right"
    case arrowLeft  = "arrow.left"
    case share  = "square.and.arrow.up"
    case edit   = "pencil"
    case link   = "link"
    case calendar = "calendar"
    case thermo = "thermometer"
    case droplet = "drop"
    case sparkle = "sparkle"
    case bell   = "bell"
    case flame  = "flame"
    case settings = "gearshape"
    case trash  = "trash"
}

struct CCIconView: View {
    let icon: CCIcon
    var size: CGFloat = 16
    var color: Color = .primary
    /// VoiceOver label. Defaults to `nil`, in which case the icon is hidden
    /// from accessibility — almost every icon in the app is decorative and
    /// paired with sibling text that's the real label. Pass a non-nil value
    /// only for icon-only contexts where the symbol itself is the meaning.
    var accessibilityLabel: String? = nil

    var body: some View {
        let img = Image(systemName: icon.rawValue)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(color)
        if let label = accessibilityLabel {
            img.accessibilityLabel(label)
        } else {
            img.accessibilityHidden(true)
        }
    }
}

// MARK: - Soft divider

struct SoftDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.border1)
            .frame(height: 1)
    }
}

// MARK: - Star rating

struct StarRating: View {
    let rating: Int   // 1...5
    var size: CGFloat = 13
    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: i <= rating ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundStyle(i <= rating ? Theme.warm : Theme.slate300)
            }
        }
    }
}
