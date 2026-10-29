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
    @EnvironmentObject private var membership: MembershipStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("satchel.guide.lastFreeQuestionAt") private var lastFreeQuestionAt: Double = 0
    @State private var currentDate = Date()
    @State private var quotaNotice: String?
    @State private var draft = ""
    @State private var messages: [GuideMessage] = []
    @State private var waiting = false
    @State private var showAllTopics = false
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var usedFreeQuestionToday: Bool {
        lastFreeQuestionAt > 0 && Calendar.current.isDate(Date(timeIntervalSince1970: lastFreeQuestionAt), inSameDayAs: currentDate)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        TabHero(artwork: "GuideHero")
                        VStack(alignment: .leading, spacing: 18) {
                            if messages.isEmpty {
                                HStack(alignment: .center, spacing: 12) {
                                    Image("NavGuide").resizable().scaledToFit().frame(width: 42, height: 42).accessibilityHidden(true)
                                    Text(l.text("Ask about packing, planning or journaling."))
                                        .font(.system(.headline, design: .serif)).fixedSize(horizontal: false, vertical: true)
                                }
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                                    ForEach(Array(GuideTopic.allCases.prefix(showAllTopics ? GuideTopic.allCases.count : 4)), id: \.question) { topic in
                                        Button { ask(l.text(topic.question)) } label: {
                                            HStack(alignment: .center, spacing: 9) {
                                                Image(topic.artwork).resizable().scaledToFit()
                                                    .frame(width: 32, height: 32).accessibilityHidden(true)
                                                Text(l.text(topic.question)).font(.subheadline.weight(.medium))
                                                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                                                Spacer(minLength: 0)
                                            }.frame(maxWidth: .infinity, minHeight: 52, alignment: .leading).padding(10)
                                                .modifier(PaperSurface(artwork: "ButtonPaper", radius: 14))
                                                .contentShape(Rectangle())
                                        }.buttonStyle(.plain)
                                    }
                                }
                                Button {
                                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { showAllTopics.toggle() }
                                } label: {
                                    HStack(spacing: 12) {
                                        Text(l.text(showAllTopics ? "Show fewer questions" : "More travel questions"))
                                            .font(.subheadline.weight(.semibold)).foregroundColor(Palette.ink)
                                            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                                        Spacer(minLength: 4)
                                        Image("MoreMarkV2").resizable().scaledToFit().frame(width: 42, height: 42)
                                            .rotationEffect(.degrees(showAllTopics ? 180 : 0)).accessibilityHidden(true)
                                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                        .padding(.horizontal, 12).padding(.vertical, 4)
                                        .modifier(PaperSurface(artwork: "ButtonSelected", radius: 16))
                                        .contentShape(Rectangle())
                                }.buttonStyle(GuideDisclosureStyle())
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
                            if let quotaNotice {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(l.text(quotaNotice)).font(.footnote).foregroundColor(Palette.muted)
                                        .fixedSize(horizontal: false, vertical: true)
                                    if membership.entitlementsReady && !membership.isMember && usedFreeQuestionToday {
                                        NavigationLink { MembershipView(l: l) } label: { Text(l.text("Satchel Membership")) }
                                            .buttonStyle(SecondaryButton())
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                            HStack(alignment: .center, spacing: 10) {
                                TextField(l.text("Ask a travel question"), text: $draft, axis: .vertical)
                                    .lineLimit(1...3).focused($focused).submitLabel(.send).onSubmit { ask(draft) }
                                    .modifier(FieldStyle())
                                Button(l.text("Send")) { ask(draft) }.buttonStyle(TabPrimaryButton())
                                    .disabled(waiting || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                            Color.clear.frame(height: 1).id("guide-bottom")
                        }.padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 18).frame(maxWidth: 700)
                            .background(Palette.paper)
                    }.frame(maxWidth: .infinity)
                }.ignoresSafeArea(.container, edges: .top)
                .onChange(of: messages.count) { _ in withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo("guide-bottom", anchor: .bottom) } }
                .onChange(of: focused) { if $0 { proxy.scrollTo("guide-bottom", anchor: .bottom) } }
                .onChange(of: quotaNotice) { if $0 != nil { proxy.scrollTo("guide-bottom", anchor: .bottom) } }
            }
        }
        .onChange(of: isActive) { active in if !active { focused = false } }
        .onChange(of: scenePhase) { phase in
            if phase == .active { currentDate = Date(); quotaNotice = nil }
        }
        .onChange(of: membership.isMember) { _ in quotaNotice = nil }
    }

    private func ask(_ question: String) {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !waiting else { return }
        currentDate = Date()
        guard membership.entitlementsReady else {
            quotaNotice = "Checking membership. Please try again in a moment."
            return
        }
        guard membership.isMember || !usedFreeQuestionToday else {
            quotaNotice = "You have used today's free question. Come back tomorrow or become a member."
            return
        }
        if !membership.isMember { lastFreeQuestionAt = currentDate.timeIntervalSince1970 }
        quotaNotice = nil
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

private struct GuideDisclosureStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : 1)
    }
}
