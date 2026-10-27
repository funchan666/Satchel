import Foundation
import UIKit
import GoogleMobileAds
import UserMessagingPlatform

@MainActor final class RewardedAds: NSObject, ObservableObject, FullScreenContentDelegate {
    private let testAdUnit = "ca-app-pub-3940256099942544/1712485313"
    @Published private(set) var privacyOptionsRequired = false
    private var active = false
    private var rewarded = false
    private var ad: RewardedAd?
    private var continuation: CheckedContinuation<String, Never>?
    private var sdkStarted = false

    func show(from controller: UIViewController?) async -> String {
        guard !active else { return "ad_busy" }
        guard let controller else { return "ad_not_ready" }
        active = true; rewarded = false
        do {
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters())
            try await ConsentForm.loadAndPresentIfRequired(from: controller)
            privacyOptionsRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
            guard ConsentInformation.shared.canRequestAds else { active = false; return "ad_not_ready" }
            if !sdkStarted {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    MobileAds.shared.start { _ in continuation.resume() }
                }
                sdkStarted = true
            }
            let loaded = try await RewardedAd.load(with: testAdUnit, request: Request())
            loaded.fullScreenContentDelegate = self; ad = loaded
            return await withCheckedContinuation { continuation in
                self.continuation = continuation
                loaded.present(from: controller) { [weak self] in self?.rewarded = true }
            }
        } catch { active = false; ad = nil; return "ad_load_failed" }
    }
    func showPrivacyOptions(from controller: UIViewController?) async throws {
        try await ConsentForm.presentPrivacyOptionsForm(from: controller)
    }
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) { finish(rewarded ? "rewarded" : "dismissed") }
    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) { finish("ad_show_failed") }
    private func finish(_ result: String) {
        let resultContinuation = continuation; continuation = nil; ad = nil; active = false
        resultContinuation?.resume(returning: result)
    }
}
