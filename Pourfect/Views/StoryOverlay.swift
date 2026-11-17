import BottleSortCore
import SwiftUI

/// A story scene (R7): the apprentice and the old alchemist stand at the bottom, the one
/// speaking lit and in front, with their line in a speech bubble above. Tap or click anywhere,
/// press Space or Return, or use "Next" to advance; "Skip" (Escape) ends the scene. With Reduce
/// Motion the lines and portraits change without sliding or bouncing. VoiceOver reads the
/// speaker and the line, and announces each new line.
struct StoryOverlay: View {
    let scene: StoryScene
    var startLine = 0
    let onFinish: () -> Void

    @Environment(LevelCatalog.self) private var catalog
    @Environment(\.effectiveReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var appeared = false
    @AccessibilityFocusState private var bubbleFocused: Bool

    private var lines: [StoryLine] { StoryScript.lines(scene) }
    private var line: StoryLine? { lines.indices.contains(index) ? lines[index] : nil }
    private var isLast: Bool { index >= lines.count - 1 }

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.width < 560
            let portrait = min(compact ? geo.size.width * 0.4 : 270, geo.size.height * 0.33)
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                if let line {
                    bubble(line, compact: compact)
                        .id(index)
                        .transition(reduceMotion ? .opacity : .asymmetric(
                            insertion: .scale(scale: 0.92, anchor: line.speaker == .alchemist ? .bottomLeading : .bottomTrailing)
                                .combined(with: .opacity),
                            removal: .opacity))
                        .padding(.horizontal, compact ? 16 : 32)
                        .frame(maxWidth: 680)
                        .onTapGesture { advance() }
                }
                portraits(size: portrait)
                    .allowsHitTesting(false)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .opacity(appeared ? 1 : 0)
            .background {
                backdrop
                    .contentShape(Rectangle())
                    .onTapGesture { advance() }
                    .accessibilityHidden(true)
            }
        }
        .onAppear {
            index = min(max(0, startLine), max(0, lines.count - 1))
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.35)) { appeared = true }
            bubbleFocused = true
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { onFinish() }
    }

    // MARK: Parts

    private var backdrop: some View {
        ZStack {
            GeometryReader { proxy in
                StoryScript.backdropImage(scene)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .blur(radius: 14, opaque: true)
                    .clipped()
                    .opacity(appeared ? 1 : 0)
            }
            LinearGradient(colors: [.black.opacity(0.45), .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack(alignment: .center) {
            Text(StoryScript.heading(scene, catalog: catalog))
                .font(.system(.subheadline, design: .serif).weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.8))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button(action: onFinish) {
                Text("Skip", comment: "Skips the rest of a story scene")
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .keyboardShortcut(.cancelAction)
            .accessibilityHint(Text("Ends the story scene"))
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private func bubble(_ line: StoryLine, compact: Bool) -> some View {
        let fromLeft = line.speaker == .alchemist
        return VStack(alignment: .leading, spacing: 8) {
            Text(line.speaker.name)
                .font(.system(.headline, design: .serif))
                .foregroundStyle(line.speaker == .alchemist ? Color(red: 0.62, green: 0.38, blue: 0.08)
                                                             : Color(red: 0.05, green: 0.42, blue: 0.42))
            Text(line.text)
                .font(compact ? .body : .title3)
                .foregroundStyle(Color(red: 0.16, green: 0.12, blue: 0.08))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                pageDots
                Spacer()
                Button(action: advance) {
                    Label(isLast ? String(localized: "Done", comment: "Ends a story scene")
                                 : String(localized: "Next", comment: "Next story line"),
                          systemImage: isLast ? "checkmark" : "chevron.right")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.55, green: 0.36, blue: 0.12))
                .keyboardShortcut(.space, modifiers: [])
                .background {
                    // Return advances too.
                    Button(action: advance) { EmptyView() }.keyboardShortcut(.defaultAction).hidden().accessibilityHidden(true)
                }
            }
            .padding(.top, 4)
        }
        .padding(compact ? 16 : 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            BubbleShape(tailOnLeft: fromLeft)
                .fill(Color(red: 0.98, green: 0.95, blue: 0.87))
                .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
        }
        .overlay { BubbleShape(tailOnLeft: fromLeft).stroke(Color(red: 0.55, green: 0.4, blue: 0.2).opacity(0.6), lineWidth: 1.5) }
        .padding(.bottom, 14)   // room for the tail
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("\(line.speaker.name): \(line.text)", comment: "VoiceOver: a story line, speaker then line"))
        .accessibilityFocused($bubbleFocused)
    }

    private var pageDots: some View {
        HStack(spacing: 5) {
            ForEach(lines.indices, id: \.self) { i in
                Circle()
                    .fill(Color(red: 0.55, green: 0.4, blue: 0.2).opacity(i == index ? 0.9 : 0.3))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Line \(index + 1) of \(lines.count)"))
    }

    /// The alchemist on the left, the apprentice on the right; the speaker is lit and larger.
    private func portraits(size: CGFloat) -> some View {
        HStack(alignment: .bottom) {
            portrait(.alchemist, size: size)
            Spacer(minLength: 0)
            portrait(.apprentice, size: size)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: 760)
        .accessibilityHidden(true)
    }

    private func portrait(_ speaker: StorySpeaker, size: CGFloat) -> some View {
        let speaking = line?.speaker == speaker
        // Each one keeps the mood of their latest line so far (neutral before they speak).
        let mood = lines.prefix(index + 1).last { $0.speaker == speaker }?.mood ?? .neutral
        return Image(speaker.portrait(mood))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .scaleEffect(speaking ? 1 : 0.86, anchor: .bottom)
            .brightness(speaking ? 0 : -0.35)
            .saturation(speaking ? 1 : 0.6)
            .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
            .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.25), value: index)
    }

    private func advance() {
        guard !isLast else { onFinish(); return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { index += 1 }
        if let line {
            AccessibilityNotification.Announcement("\(line.speaker.name): \(line.text)").post()
        }
    }
}

/// A rounded speech bubble with a small tail at the bottom, on the speaker's side.
private struct BubbleShape: Shape {
    let tailOnLeft: Bool

    func path(in rect: CGRect) -> Path {
        let body = Path(roundedRect: rect, cornerRadius: 18)
        let x = tailOnLeft ? rect.minX + rect.width * 0.18 : rect.maxX - rect.width * 0.18
        let dir: CGFloat = tailOnLeft ? -1 : 1
        var tail = Path()
        tail.move(to: CGPoint(x: x - 14, y: rect.maxY - 1))
        tail.addLine(to: CGPoint(x: x + dir * 10, y: rect.maxY + 14))
        tail.addLine(to: CGPoint(x: x + 14, y: rect.maxY - 1))
        tail.closeSubpath()
        return body.union(tail)
    }
}
