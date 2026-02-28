import SwiftUI
import UIKit

// MARK: - LiquidDrop

@MainActor
public struct LiquidDrop: Identifiable {
    public init(
        title: String,
        subtitle: String? = nil,
        icon: UIImage? = nil,
        action: Action? = nil,
        duration: TimeInterval = 3.0,
        effectStyle: EffectStyle = .regular,
        glassTint: Color? = .clear
    ) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = UUID()
        self.title = trimmedTitle
        if let subtitle {
            let trimmedSubtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
            self.subtitle = trimmedSubtitle.isEmpty ? nil : trimmedSubtitle
        } else {
            self.subtitle = nil
        }
        self.icon = icon
        self.action = action
        self.duration = duration
        self.effectStyle = effectStyle
        self.glassTint = glassTint
    }

    public let id: UUID
    public let title: String
    public let subtitle: String?
    public let icon: UIImage?
    public let action: Action?
    public let duration: TimeInterval
    public let effectStyle: EffectStyle
    public let glassTint: Color?
}

public extension LiquidDrop {
    enum EffectStyle: Equatable {
        case regular
        case clear
    }
}

public extension LiquidDrop {
    struct Action {
        public init(icon: UIImage? = nil, handler: @escaping () -> Void) {
            self.icon = icon
            self.handler = handler
        }

        public var icon: UIImage?
        public var handler: () -> Void
    }
}

// MARK: - LiquidDrops

@MainActor
public final class LiquidDrops: ObservableObject {
    public static let shared = LiquidDrops()

    public static func show(_ drop: LiquidDrop) {
        shared.show(drop)
    }

    public static func hideCurrent() {
        shared.hideCurrent()
    }

    public static func hideAll() {
        shared.hideAll()
    }

    @Published fileprivate var currentDrop: LiquidDrop?
    @Published fileprivate var visibility: CGFloat = 0

    fileprivate func beginInteraction() {
        autoHideTask?.cancel()
        autoHideTask = nil
    }

    fileprivate func endInteraction() {
        queueAutoHideIfNeeded()
    }

    public func show(_ drop: LiquidDrop) {
        queue.append(drop)
        guard let currentDrop else {
            presentNextIfNeeded()
            return
        }
        hide(dropID: currentDrop.id, animated: true, bypassQueueDelay: true)
    }

    public func hideCurrent() {
        guard let currentDrop else { return }
        hide(dropID: currentDrop.id, animated: true)
    }

    public func hideAll() {
        queue.removeAll()
        hideCurrent()
    }

    // MARK: Private

    private var queue: [LiquidDrop] = []
    private var autoHideTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?

    private static let entranceAnimation: Animation = .snappy(duration: 0.4, extraBounce: 0.12)
    private static let exitAnimation: Animation = .smooth(duration: 0.26)
    private static let exitDuration: TimeInterval = 0.26
    private static let delayBetweenDrops: TimeInterval = 0.5

    private func presentNextIfNeeded() {
        guard currentDrop == nil, !queue.isEmpty else { return }
        let next = queue.removeFirst()

        currentDrop = next
        visibility = 0

        withAnimation(Self.entranceAnimation) {
            visibility = 1
        }

        let a11yMessage = [next.title, next.subtitle].compactMap { $0 }.joined(separator: ", ")
        UIAccessibility.post(notification: .announcement, argument: a11yMessage)
        queueAutoHideIfNeeded()
    }

    private func queueAutoHideIfNeeded() {
        autoHideTask?.cancel()
        guard let currentDrop else { return }

        autoHideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(currentDrop.duration))
            guard !Task.isCancelled else { return }
            await self?.hide(dropID: currentDrop.id, animated: true)
        }
    }

    private func hide(dropID: UUID, animated: Bool, bypassQueueDelay: Bool = false) {
        guard let currentDrop, currentDrop.id == dropID else { return }

        autoHideTask?.cancel()
        autoHideTask = nil

        if animated {
            withAnimation(Self.exitAnimation) {
                visibility = 0
            }
        } else {
            visibility = 0
        }

        hideTask?.cancel()
        hideTask = Task { [weak self] in
            guard let self else { return }

            if animated {
                try? await Task.sleep(for: .seconds(Self.exitDuration + 0.02))
            }

            guard let stillCurrent = self.currentDrop, stillCurrent.id == dropID else { return }
            self.currentDrop = nil

            if !bypassQueueDelay {
                try? await Task.sleep(for: .seconds(Self.delayBetweenDrops))
            }
            guard !Task.isCancelled else { return }
            self.presentNextIfNeeded()
        }
    }
}

// MARK: - Host Modifier

public extension View {
    func liquidDropsHost() -> some View {
        modifier(LiquidDropsHostModifier())
    }
}

private struct LiquidDropsHostModifier: ViewModifier {
    @StateObject private var drops = LiquidDrops.shared

    func body(content: Content) -> some View {
        ZStack {
            content
            LiquidDropsOverlay(drops: drops)
                .zIndex(999)
        }
    }
}

// MARK: - Overlay

private struct LiquidDropsOverlay: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var drops: LiquidDrops
    @State private var dragOffset: CGFloat = 0
    @State private var isGestureDismissing = false
    @State private var islandBeatHapticsTask: Task<Void, Never>?
    @State private var cardBaseSize: CGSize = CGSize(width: 280, height: 56)

    private var foregroundColor: Color {
        colorScheme == .light ? .black : .white
    }

    var body: some View {
        GeometryReader { proxy in
            if let drop = drops.currentDrop {
                topContainer(for: drop, safeArea: proxy.safeAreaInsets, canvasSize: proxy.size)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onChange(of: drop.id) { _, _ in
                        dragOffset = 0
                        isGestureDismissing = false
                        islandBeatHapticsTask?.cancel()
                        islandBeatHapticsTask = nil
                    }
                    .task(id: drop.id) {
                        scheduleIslandBeatHaptics(canvasSize: proxy.size, topInset: proxy.safeAreaInsets.top)
                    }
            }
        }
        .allowsHitTesting(drops.currentDrop != nil)
        .ignoresSafeArea()
        .onChange(of: drops.currentDrop?.id) { _, newValue in
            if newValue == nil {
                islandBeatHapticsTask?.cancel()
                islandBeatHapticsTask = nil
            }
        }
    }

    // MARK: Container

    @ViewBuilder
    private func topContainer(for drop: LiquidDrop, safeArea: EdgeInsets, canvasSize: CGSize) -> some View {
        let topInset = max(safeArea.top, 44)
        let t = clamped(drops.visibility, to: 0...1)
        let hasDynamicIsland = UIDevice.current.userInterfaceIdiom == .phone && topInset >= 54
        let islandFrame = dynamicIslandFrame(topInset: topInset, canvasWidth: canvasSize.width)
        let isPortrait = canvasSize.height >= canvasSize.width
        let showIslandBeat = hasDynamicIsland && isPortrait

        ZStack(alignment: .top) {
            if showIslandBeat {
                islandLaunchCapsule(islandFrame: islandFrame, progress: t)
            }

            if hasDynamicIsland {
                card(for: drop, cornerRadius: topCornerRadius(for: t, islandFrame: islandFrame))
                    .readSize { size in
                        guard size.width > 0, size.height > 0 else { return }
                        cardBaseSize = size
                    }
                    .scaleEffect(
                        x: topScale(for: t, islandFrame: islandFrame, cardSize: cardBaseSize).width,
                        y: topScale(for: t, islandFrame: islandFrame, cardSize: cardBaseSize).height,
                        anchor: .top
                    )
                    .offset(y: topY(for: t, topInset: topInset, islandFrame: islandFrame) + dragOffset)
                    .shadow(
                        color: .black.opacity(0.18 * topShadowAmount(for: t)),
                        radius: 20 * topShadowAmount(for: t),
                        y: 9 * topShadowAmount(for: t)
                    )
            } else {
                let restingY = topInset + 8
                card(for: drop)
                    .readSize { size in
                        guard size.width > 0, size.height > 0 else { return }
                        cardBaseSize = size
                    }
                    .offset(y: lerp(from: -80, to: restingY, t: t) + dragOffset)
                    .opacity(Double(t))
                    .shadow(
                        color: .black.opacity(0.18 * topShadowAmount(for: t)),
                        radius: 20 * topShadowAmount(for: t),
                        y: 9 * topShadowAmount(for: t)
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Island Beat

    private func scheduleIslandBeatHaptics(canvasSize: CGSize, topInset: CGFloat) {
        islandBeatHapticsTask?.cancel()
        islandBeatHapticsTask = nil

        let hasDynamicIsland = UIDevice.current.userInterfaceIdiom == .phone && topInset >= 54
        let isPortrait = canvasSize.height >= canvasSize.width
        guard hasDynamicIsland && isPortrait else { return }

        islandBeatHapticsTask = Task { @MainActor in
            let first = UIImpactFeedbackGenerator(style: .medium)
            first.prepare()
            first.impactOccurred(intensity: 0.95)

            try? await Task.sleep(for: .milliseconds(130))
            guard !Task.isCancelled else { return }

            let second = UIImpactFeedbackGenerator(style: .soft)
            second.prepare()
            second.impactOccurred(intensity: 0.7)
        }
    }

    private func islandLaunchCapsule(islandFrame: CGRect, progress: CGFloat) -> some View {
        let t = clamped(progress, to: 0...1)
        return Capsule(style: .continuous)
            .fill(.black)
            .frame(width: islandFrame.width, height: islandFrame.height)
            .offset(y: islandFrame.minY + islandBeatYOffset(for: t))
            .scaleEffect(islandBeatScale(for: t))
            .opacity(islandBeatOpacity(for: t))
            .allowsHitTesting(false)
    }

    private func dynamicIslandFrame(topInset: CGFloat, canvasWidth: CGFloat) -> CGRect {
        let isiPhone = UIDevice.current.userInterfaceIdiom == .phone
        let hasLikelyIsland = isiPhone && topInset >= 54

        let width: CGFloat = hasLikelyIsland ? 126 : 108
        let height: CGFloat = hasLikelyIsland ? 37 : 32
        let centeredTop = max(0, (topInset - height) * 0.5)
        let topY: CGFloat = hasLikelyIsland
            ? centeredTop
            : max(8, centeredTop)

        return CGRect(
            x: (canvasWidth - width) / 2,
            y: topY,
            width: width,
            height: height
        )
    }

    private func islandBeatScale(for progress: CGFloat) -> CGFloat {
        let t = clamped(progress, to: 0...1)
        if t < 0.06 {
            return 1
        } else if t < 0.28 {
            let phase = clamped((t - 0.06) / 0.22, to: 0...1)
            return 1 + (0.17 * sin(phase * .pi))
        } else if t < 0.46 {
            let phase = clamped((t - 0.28) / 0.18, to: 0...1)
            return 1 + (0.09 * sin(phase * .pi))
        } else {
            return 1
        }
    }

    private func islandBeatYOffset(for progress: CGFloat) -> CGFloat {
        let t = clamped(progress, to: 0...1)
        if t < 0.06 {
            return 0
        } else if t < 0.28 {
            let phase = clamped((t - 0.06) / 0.22, to: 0...1)
            return -3.2 * sin(phase * .pi)
        } else if t < 0.46 {
            let phase = clamped((t - 0.28) / 0.18, to: 0...1)
            return -1.8 * sin(phase * .pi)
        } else {
            return 0
        }
    }

    private func islandBeatOpacity(for progress: CGFloat) -> CGFloat {
        let t = clamped(progress, to: 0...1)
        return 1 - clamped((t - 0.18) / 0.44, to: 0...1)
    }

    // MARK: DI Animation Math

    private func topScale(for progress: CGFloat, islandFrame: CGRect, cardSize: CGSize) -> CGSize {
        let t = clamped(progress, to: 0...1)
        let expandCutoff: CGFloat = 0.42
        let safeWidth = max(cardSize.width, 1)
        let safeHeight = max(cardSize.height, 1)

        let startWidthScale = islandFrame.width / safeWidth
        let startHeightScale = islandFrame.height / safeHeight

        if t < expandCutoff {
            let phase = clamped(t / expandCutoff, to: 0...1)
            return CGSize(
                width: lerp(from: startWidthScale, to: 1.08, t: phase),
                height: lerp(from: startHeightScale, to: 1.05, t: phase)
            )
        } else {
            let phase = clamped((t - expandCutoff) / (1 - expandCutoff), to: 0...1)
            return CGSize(
                width: lerp(from: 1.08, to: 1, t: phase),
                height: lerp(from: 1.05, to: 1, t: phase)
            )
        }
    }

    private func topY(for progress: CGFloat, topInset: CGFloat, islandFrame: CGRect) -> CGFloat {
        let t = clamped(progress, to: 0...1)
        let start = islandFrame.minY
        let end = topInset + 8
        let mid = min(end, start + 18)
        let cutoff: CGFloat = 0.42

        if t < cutoff {
            let phase = clamped(t / cutoff, to: 0...1)
            return lerp(from: start, to: mid, t: phase)
        } else {
            let phase = clamped((t - cutoff) / (1 - cutoff), to: 0...1)
            return lerp(from: mid, to: end, t: phase)
        }
    }

    private func topCornerRadius(for progress: CGFloat, islandFrame: CGRect) -> CGFloat {
        let t = clamped(progress, to: 0...1)
        let cutoff: CGFloat = 0.42
        let startRadius = islandFrame.height * 0.5

        if t < cutoff {
            let phase = clamped(t / cutoff, to: 0...1)
            return lerp(from: startRadius, to: 28, t: phase)
        } else {
            let phase = clamped((t - cutoff) / (1 - cutoff), to: 0...1)
            return lerp(from: 28, to: 24, t: phase)
        }
    }

    private func topShadowAmount(for progress: CGFloat) -> CGFloat {
        clamped((progress - 0.12) / 0.88, to: 0...1)
    }

    // MARK: Card

    private func card(for drop: LiquidDrop, cornerRadius: CGFloat = 24) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return HStack(spacing: 14) {
            if let icon = drop.icon {
                Image(uiImage: icon)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(foregroundColor)
            }

            VStack(alignment: .leading, spacing: drop.subtitle == nil ? 0 : 2) {
                Text(drop.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(foregroundColor)

                if let subtitle = drop.subtitle {
                    Text(subtitle)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(foregroundColor.opacity(0.78))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            if let actionIcon = drop.action?.icon {
                Button {
                    drop.action?.handler()
                } label: {
                    Image(uiImage: actionIcon)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                        .frame(width: 32, height: 32)
                        .background(foregroundColor.opacity(0.16), in: Circle())
                        .foregroundStyle(foregroundColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, drop.subtitle == nil ? 14 : 10)
        .padding(.horizontal, 14)
        .background {
            if #available(iOS 26, *) {
                if drop.effectStyle == .clear {
                    shape
                        .fill(.clear)
                        .glassEffect(
                            .clear.tint((drop.glassTint ?? .cyan).opacity(0.14)),
                            in: shape
                        )
                } else {
                    shape
                        .fill(.clear)
                        .glassEffect(
                            .regular.tint((drop.glassTint ?? .cyan).opacity(0.2)),
                            in: shape
                        )
                }
            } else {
                shape
                    .fill(.ultraThinMaterial)
            }
        }
        .frame(maxWidth: 380)
        .contentShape(shape)
        .onTapGesture {
            if let action = drop.action, action.icon == nil {
                action.handler()
            }
        }
        .gesture(dragGesture())
        .padding(.horizontal, 20)
    }

    // MARK: Drag Gesture

    private func dragGesture() -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard !isGestureDismissing else { return }
                drops.beginInteraction()

                if value.translation.height < 0 {
                    if value.translation.height <= -18 {
                        isGestureDismissing = true
                        dragOffset = 0
                        drops.hideCurrent()
                        return
                    }
                    dragOffset = value.translation.height
                } else {
                    dragOffset = value.translation.height * 0.2
                }
            }
            .onEnded { value in
                guard !isGestureDismissing else {
                    isGestureDismissing = false
                    return
                }
                if value.predictedEndTranslation.height < -78 {
                    drops.hideCurrent()
                } else {
                    withAnimation(.spring(duration: 0.34, bounce: 0.2)) {
                        dragOffset = 0
                    }
                    drops.endInteraction()
                }
            }
    }
}

// MARK: - Helpers

private func lerp(from: CGFloat, to: CGFloat, t: CGFloat) -> CGFloat {
    from + (to - from) * t
}

private func clamped(_ value: CGFloat, to limits: ClosedRange<CGFloat>) -> CGFloat {
    min(max(value, limits.lowerBound), limits.upperBound)
}

private struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

private extension View {
    func readSize(_ onChange: @escaping (CGSize) -> Void) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: SizePreferenceKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(SizePreferenceKey.self, perform: onChange)
    }
}

// MARK: - Previews

#Preview("Bubble") {
    LiquidDropBubblePreview()
}

private struct LiquidDropBubblePreview: View {
    @StateObject private var drops = LiquidDrops()

    private let sampleDrop = LiquidDrop(
        title: "Copied to clipboard",
        subtitle: "Paste anywhere",
        icon: UIImage(systemName: "doc.on.doc.fill")
    )

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            LiquidDropsOverlay(drops: drops)
        }
        .onAppear {
            drops.currentDrop = sampleDrop
            drops.visibility = 1
        }
    }
}

#Preview("Interactive") {
    VStack {
        ScrollView {}

        Button("Show Drop") {
            LiquidDrops.show(LiquidDrop(
                title: "Invalid Grade",
                subtitle: "Only enter a grade range 0-100 or mathematical expression.",
                icon: UIImage(systemName: "xmark.circle.fill")
            ))
        }
    }
    .liquidDropsHost()
}
