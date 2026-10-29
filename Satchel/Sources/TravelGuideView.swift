import SwiftUI

private struct GuideMessage: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
}

private enum GuideTopic: CaseIterable {
    case packing, rain, journal, flight, budget, beach

    var artwork: String {
        switch self {
        case .packing: return "NavTrips"
        case .rain: return "TravelTicket"
        case .journal: return "SeaJournal"
        case .flight: return "NavMe"
        case .budget: return "MembershipArt"
        case .beach: return "NavGuide"
        }
    }
    var question: String {
        switch self {
        case .packing: return "What should I pack?"
        case .rain: return "What if it rains?"
        case .journal: return "How do I keep a travel journal?"
        case .flight: return "What should I check before flying?"
        case .budget: return "How can I plan a travel budget?"
        case .beach: return "What should I pack for the beach?"
        }
    }
    var answer: String {
        switch self {
        case .packing: return "Start with essentials, then pack interchangeable layers. Add your charger, toiletries and any medication; check your route and luggage rules before leaving."
        case .rain: return "Pack a light waterproof layer, a small umbrella and a dry bag for electronics. Choose shoes that dry quickly and keep a flexible indoor plan. Check the local forecast before you go."
        case .journal: return "Capture one small moment each day: where you were, what surprised you and how it felt. Add a photo or a ticket, then leave a note for your next visit."
        case .flight: return "Check your passport and entry requirements with official sources, then confirm baggage rules and flight times with your airline. Keep documents, medication and a charger in your carry-on."
        case .budget: return "Start with transport and accommodation, then set a daily amount for food and activities. Keep a separate buffer for changes, and note the currency and payment fees."
        case .beach: return "Bring sun protection, a hat, water and a quick-dry layer. Add a small waterproof pouch and check local conditions before swimming."
        }
    }
    var keywords: [String] {
        switch self {
        case .packing: return ["pack", "luggage", "suitcase", "行李", "打包", "收拾", "荷物", "짐", "maleta", "bagage", "packen", "bagagem"]
        case .rain: return ["rain", "weather", "下雨", "天气", "天氣", "雨", "날씨", "비가", "비옷", "비 오", "lluvia", "pluie", "regen", "chuva"]
        case .journal: return ["journal", "memory", "diary", "手账", "手帳", "日记", "日記", "回忆", "回憶", "思い出", "기록", "diario", "souvenir", "tagebuch", "diário"]
        case .flight: return ["flight", "fly", "passport", "airport", "飞机", "飛機", "护照", "護照", "航班", "飛行機", "여권", "비행", "vuelo", "vol", "flug", "voo"]
        case .budget: return ["budget", "money", "cost", "预算", "預算", "花费", "花費", "予算", "예산", "presupuesto", "budget", "custo", "orçamento"]
        case .beach: return ["beach", "sea", "seaside", "海边", "海邊", "海滩", "海灘", "海水浴", "해변", "playa", "plage", "strand", "praia"]
        }
    }
}

struct TravelGuideView: View {
    let l: L10n
    let isActive: Bool
    @State private var draft = ""
    @State private var messages: [GuideMessage] = []
    @State private var waiting = false
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if messages.isEmpty {
                            ZStack(alignment: .bottomLeading) {
                                EditorialBanner(artwork: "GuideHero", height: 235)
                                HStack(alignment: .center, spacing: 12) {
                                    Image("NavGuide").resizable().scaledToFit().frame(width: 52, height: 52).accessibilityHidden(true)
                                    Text(l.text("Ask about packing, planning or journaling."))
                                        .font(.system(size: 20, design: .serif)).fixedSize(horizontal: false, vertical: true)
                                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                    .modifier(SatchelGlass(tint: Palette.cream.opacity(0.5), cornerRadius: 16)).padding(12)
                            }
                        }
                        if messages.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(GuideTopic.allCases, id: \.question) { topic in
                                        Button { ask(l.text(topic.question)) } label: {
                                            VStack(alignment: .leading, spacing: 10) {
                                                Image(topic.artwork)
                                                    .resizable().scaledToFit().frame(width: 46, height: 46).accessibilityHidden(true)
                                                Text(l.text(topic.question)).font(.subheadline.weight(.medium)).multilineTextAlignment(.leading)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }.frame(width: 150).frame(minHeight: 126, alignment: .topLeading).padding(14)
                                                .modifier(SatchelGlass(tint: Palette.cream.opacity(0.25), interactive: true, cornerRadius: 16))
                                        }.buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        ForEach(messages) { message in
                            HStack {
                                if message.isUser { Spacer(minLength: 40) }
                                Text(message.text).font(.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                    .padding(15).foregroundColor(message.isUser ? .white : Palette.ink)
                                    .background(message.isUser ? Palette.ocean : Palette.cream, in: RoundedRectangle(cornerRadius: 18))
                                if !message.isUser { Spacer(minLength: 24) }
                            }
                        }
                        if waiting { Text(l.text("Preparing a tip…")).font(.footnote).foregroundColor(Palette.muted).accessibilityLabel(l.text("Preparing a tip…")) }
                        Color.clear.frame(height: 1).id("guide-bottom")
                    }.padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 18).frame(maxWidth: 700)
                }
                .onChange(of: messages.count) { _ in withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo("guide-bottom", anchor: .bottom) } }
            }
            HStack(alignment: .center, spacing: 10) {
                TextField(l.text("Ask a travel question"), text: $draft, axis: .vertical)
                    .lineLimit(1...3).focused($focused).submitLabel(.send).onSubmit { ask(draft) }
                    .modifier(FieldStyle())
                Button(l.text("Send")) { ask(draft) }.buttonStyle(PrimaryButton())
                    .disabled(waiting || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding(.horizontal, 20).padding(.vertical, 10).frame(maxWidth: 700)
        }
        .onChange(of: isActive) { active in if !active { focused = false } }
    }

    private func ask(_ question: String) {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !waiting else { return }
        let normalized = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let suggested = GuideTopic.allCases.first { l.text($0.question).compare(text, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
        // Specific situations take precedence over a generic packing question.
        let order: [GuideTopic] = [.rain, .flight, .budget, .beach, .journal, .packing]
        let topic = suggested ?? order.first { item in item.keywords.contains { normalized.contains($0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)) } }
        let answer = l.text(topic?.answer ?? "I can help with packing, rain, flights, budgets, beaches and travel journals. Try one of these topics.")
        messages.append(GuideMessage(text: text, isUser: true))
        draft = ""; waiting = true; focused = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            messages.append(GuideMessage(text: answer, isUser: false))
            waiting = false
        }
    }
}
