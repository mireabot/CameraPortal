//
//  ChatInputBar.swift
//  CameraPortal
//
//  The input panel. Telegram's structure and insets
//  (submodules/TelegramUI/.../ChatTextInputPanelNode.swift), with one deliberate deviation:
//  - attach button 40x40 there (:3559, :3561), **44x44 here** — every round control in this
//    feature is one size, and the attach button is one of them
//  - text field height = minimalInputHeight 40 there (31pt text box + 5 top + 4 bottom),
//    **44 here** so the row still reads as one bar beside a 44pt button; the 35pt text box
//    is what the same 5/4 insets leave inside it
//  - radius floor(height * 0.5): 20 there, **22 here**, by the same rule
//  - textFieldInsets: leading 8 + (button + 6), trailing 8 (:1473) — unchanged, the button
//    term just grew with the button
//  - textInputViewInternalInsets: top 5, leading 12, bottom 4, trailing 11 (:710) — unchanged
//
//  The attach button itself is *not* drawn here: it is the collapsed state of the morph
//  surface, which lives in the overlay layer so it can grow into the tray. This bar leaves
//  its slot empty and the surface lands exactly in it.
//

import SwiftUI

struct ChatInputBar: View {
    /// The row's height, and the attach button's size. 44 rather than Telegram's 40: it is
    /// `TrayCameraConfig.controlButtonSize`, the one round-control size in the feature.
    static let height: CGFloat = TrayCameraConfig.controlButtonSize
    /// Telegram's outer `textFieldInsets` left/right.
    static let horizontalInset: CGFloat = 8
    /// Gap between the attach button and the text field.
    static let attachSpacing: CGFloat = 6

    /// Owned by the chat screen, because opening the tray has to resign it — a keyboard
    /// sliding out from under the tray reads as two screens fighting.
    @FocusState.Binding var isFocused: Bool

    @State private var text = ""

    var body: some View {
        HStack(spacing: Self.attachSpacing) {
            Color.clear
                .frame(width: Self.height, height: Self.height)
                .accessibilityHidden(true)

            textField
        }
        .padding(.horizontal, Self.horizontalInset)
        .padding(.bottom, Self.horizontalInset)
    }

    private var textField: some View {
        // Single line on purpose: `axis: .vertical` would let the row grow with the text, and
        // the row's height is what the collapsed morph surface is positioned against.
        TextField("Message", text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 17))
            .focused($isFocused)
            .submitLabel(.send)
            .onSubmit { text = "" }
            // Telegram's asymmetric 5/4 insets, kept; the text box is whatever they leave
            // inside our 44pt row (35), where Telegram's 40pt row leaves 31.
            .frame(maxWidth: .infinity, minHeight: Self.height - 5 - 4, alignment: .leading)
            .padding(EdgeInsets(top: 5, leading: 12, bottom: 4, trailing: 11))
            .glassEffect(
                .regular.tint(Color.primary.opacity(0.04)),
                in: .rect(cornerRadius: (Self.height * 0.5).rounded(.down), style: .continuous)
            )
    }
}

// MARK: - Placeholder conversation

struct ChatMessage: Identifiable {
    let id: Int
    let text: String
    let isOutgoing: Bool

    static let samples = [
        ChatMessage(id: 0, text: "Did you get the shots from yesterday?", isOutgoing: false),
        ChatMessage(id: 1, text: "Sending them now", isOutgoing: true),
        ChatMessage(id: 2, text: "Tap the paperclip — the tray grows out of it", isOutgoing: false),
        ChatMessage(id: 3, text: "One glass surface the whole way", isOutgoing: true),
    ]
}

struct ChatMessageList: View {
    var messages: [ChatMessage]

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(messages) { message in
                    ChatBubble(message: message)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .defaultScrollAnchor(.bottom)
        .scrollIndicators(.hidden)
    }
}

struct ChatBubble: View {
    var message: ChatMessage

    var body: some View {
        // Spacers rather than a max width: the bubble keeps its intrinsic width and the
        // leftover 25% is what stops a long message from filling the row edge to edge.
        HStack(spacing: 0) {
            if message.isOutgoing { Spacer(minLength: 64) }

            Text(message.text)
                .font(.system(size: 16))
                .foregroundStyle(message.isOutgoing ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    message.isOutgoing ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary),
                    in: .rect(cornerRadius: 18, style: .continuous)
                )

            if !message.isOutgoing { Spacer(minLength: 64) }
        }
    }
}

#Preview {
    @Previewable @FocusState var isFocused: Bool

    VStack(spacing: 0) {
        ChatMessageList(messages: ChatMessage.samples)
        ChatInputBar(isFocused: $isFocused)
    }
}
