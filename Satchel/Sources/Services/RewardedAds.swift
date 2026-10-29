import Foundation
import UIKit
import GoogleMobileAds
import UserMessagingPlatform

@MainActor final class RewardedAds: NSObject, ObservableObject, FullScreenContentDelegate {
    private let testAdUnit = "ca-app-pub-3940256099942544/1712485313"
    private let testInterstitialUnit = "ca-app-pub-3940256099942544/4411468910"
    private let testAppOpenUnit = "ca-app-pub-3940256099942544/5575463023"
    @Published private(set) var privacyOptionsRequired = false
    private var active = false
    var isPresentingFullScreen: Bool { active }
    private(set) var openConsentInProgress = false
    private(set) var openAdIsPresenting = false
    private var openAttempt: UUID?
    private var appOpenAd: AppOpenAd?
    private var rewarded = false
    private var ad: RewardedAd?
    private var interstitial: InterstitialAd?
    private var continuation: CheckedContinuation<String, Never>?
    private var sdkStarted = false

    func cancelPendingOpen() {
        guard openAttempt != nil, !openConsentInProgress, !openAdIsPresenting else { return }
        openAttempt = nil
        active = false
    }

    func showAppOpen(from controller: UIViewController, shouldPresent: @escaping () -> Bool) async -> String {
        guard !active, controller.viewIfLoaded?.window != nil else { return "ad_not_ready" }
        let attempt = UUID()
        openAttempt = attempt
        active = true; rewarded = false
        do {
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters())
            guard openAttempt == attempt, shouldPresent() else { cancelPendingOpen(); return "ad_not_ready" }
            openConsentInProgress = true
            do { try await ConsentForm.loadAndPresentIfRequired(from: controller) }
            catch { openConsentInProgress = false; throw error }
            openConsentInProgress = false
            privacyOptionsRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
            guard openAttempt == attempt, shouldPresent(), ConsentInformation.shared.canRequestAds else {
                cancelPendingOpen(); return "ad_not_ready"
            }
            if !sdkStarted {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    MobileAds.shared.start { _ in continuation.resume() }
                }
                guard openAttempt == attempt else { return "ad_not_ready" }
                sdkStarted = true
            }
            let loaded = try await AppOpenAd.load(with: testAppOpenUnit, request: Request())
            guard openAttempt == attempt, shouldPresent(), controller.viewIfLoaded?.window != nil,
                  UIApplication.shared.applicationState == .active else {
                cancelPendingOpen(); return "ad_not_ready"
            }
            try loaded.canPresent(from: controller)
            loaded.fullScreenContentDelegate = self
            appOpenAd = loaded
            openAdIsPresenting = true
            return await withCheckedContinuation { continuation in
                self.continuation = continuation
                loaded.present(from: controller)
            }
        } catch {
            if openAttempt == attempt { openConsentInProgress = false; openAttempt = nil; active = false }
            return "ad_load_failed"
        }
    }

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
    func showInterstitial(from controller: UIViewController?) async -> String {
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
            let loaded = try await InterstitialAd.load(with: testInterstitialUnit, request: Request())
            loaded.fullScreenContentDelegate = self; interstitial = loaded
            return await withCheckedContinuation { continuation in
                self.continuation = continuation
                loaded.present(from: controller)
            }
        } catch { active = false; interstitial = nil; return "ad_load_failed" }
    }
    func showPrivacyOptions(from controller: UIViewController?) async throws {
        try await ConsentForm.presentPrivacyOptionsForm(from: controller)
    }
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) { finish(interstitial != nil ? "dismissed" : (rewarded ? "rewarded" : "dismissed")) }
    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) { finish("ad_show_failed") }
    private func finish(_ result: String) {
        let resultContinuation = continuation; continuation = nil; ad = nil; interstitial = nil; appOpenAd = nil; openAttempt = nil; openAdIsPresenting = false; active = false
        resultContinuation?.resume(returning: result)
    }
}
