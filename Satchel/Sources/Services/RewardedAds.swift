import Foundation
import UIKit
import GoogleMobileAds
import UserMessagingPlatform
import OSLog

@MainActor final class RewardedAds: NSObject, ObservableObject, FullScreenContentDelegate {
    private let testAdUnit = "ca-app-pub-3940256099942544/1712485313"
    private let testInterstitialUnit = "ca-app-pub-3940256099942544/4411468910"
    private let testAppOpenUnit = "ca-app-pub-3940256099942544/5575463023"
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
    private let openLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Satchel", category: "AppOpenAd")

    func cancelPendingOpen() {
        guard openAttempt != nil, !openConsentInProgress, !openAdIsPresenting else { return }
        openLog.info("Startup ad attempt cancelled before presentation")
        openAttempt = nil
        active = false
    }

    func showAppOpen(from controller: UIViewController, shouldPresent: @escaping () -> Bool) async -> String {
        guard !active, controller.viewIfLoaded?.window != nil else {
            openLog.info("Startup ad presenter unavailable or another ad is active")
            return "ad_not_ready"
        }
        let attempt = UUID()
        openAttempt = attempt
        active = true; rewarded = false
        var stage = "consent-update"
        var consentUpdated = false
        openLog.info("Startup ad consent update started")
        do {
            do {
                try await ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters())
                consentUpdated = true
            }
            catch {
                let failure = error as NSError
                openLog.error("Consent update failed: domain=\(failure.domain, privacy: .public), code=\(failure.code)")
                // UMP may still allow requests using a previous session's consent.
                guard ConsentInformation.shared.canRequestAds else { throw error }
            }
            guard await waitForForeground(attempt: attempt, controller: controller, shouldPresent: shouldPresent) else { cancelPendingOpen(); return "ad_not_ready" }
            if consentUpdated {
                stage = "consent-form"
                openConsentInProgress = true
                do { try await ConsentForm.loadAndPresentIfRequired(from: controller) }
                catch { openConsentInProgress = false; throw error }
                openConsentInProgress = false
            }
            guard ConsentInformation.shared.canRequestAds,
                  await waitForForeground(attempt: attempt, controller: controller, shouldPresent: shouldPresent) else {
                openLog.info("Startup ad cannot request ads or startup is no longer active")
                cancelPendingOpen(); return "ad_not_ready"
            }
            if !sdkStarted {
                stage = "sdk-start"
                openLog.info("Startup ad SDK initialization started")
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    MobileAds.shared.start { _ in continuation.resume() }
                }
                guard openAttempt == attempt else { return "ad_not_ready" }
                sdkStarted = true
            }
            stage = "load"
            openLog.info("Startup test ad load started")
            let loaded = try await AppOpenAd.load(with: testAppOpenUnit, request: Request())
            guard await waitForForeground(attempt: attempt, controller: controller, shouldPresent: shouldPresent) else {
                cancelPendingOpen(); return "ad_not_ready"
            }
            stage = "presentation"
            try loaded.canPresent(from: controller)
            loaded.fullScreenContentDelegate = self
            appOpenAd = loaded
            openAdIsPresenting = true
            openLog.info("Startup ad presenting")
            return await withCheckedContinuation { continuation in
                self.continuation = continuation
                loaded.present(from: controller)
            }
        } catch {
            let failure = error as NSError
            openLog.error("Startup ad failed at \(stage, privacy: .public): domain=\(failure.domain, privacy: .public), code=\(failure.code)")
            if openAttempt == attempt { openConsentInProgress = false; openAttempt = nil; active = false }
            return "ad_load_failed"
        }
    }

    private func waitForForeground(attempt: UUID, controller: UIViewController, shouldPresent: () -> Bool) async -> Bool {
        while openAttempt == attempt && shouldPresent() && !Task.isCancelled {
            if controller.viewIfLoaded?.window?.windowScene?.activationState == .foregroundActive,
               UIApplication.shared.applicationState == .active { return true }
            do { try await Task.sleep(nanoseconds: 200_000_000) } catch { return false }
        }
        return false
    }

    func show(from controller: UIViewController?) async -> String {
        guard !active else { return "ad_busy" }
        guard let controller else { return "ad_not_ready" }
        active = true; rewarded = false
        do {
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters())
            try await ConsentForm.loadAndPresentIfRequired(from: controller)
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
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        if appOpenAd != nil { openLog.info("Startup ad dismissed") }
        finish(interstitial != nil ? "dismissed" : (rewarded ? "rewarded" : "dismissed"))
    }
    func adDidRecordImpression(_ ad: FullScreenPresentingAd) {
        if appOpenAd != nil { openLog.info("Startup ad impression recorded") }
    }
    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        if appOpenAd != nil {
            let failure = error as NSError
            openLog.error("Startup ad presentation failed: domain=\(failure.domain, privacy: .public), code=\(failure.code)")
        }
        finish("ad_show_failed")
    }
    private func finish(_ result: String) {
        let resultContinuation = continuation; continuation = nil; ad = nil; interstitial = nil; appOpenAd = nil; openAttempt = nil; openAdIsPresenting = false; active = false
        resultContinuation?.resume(returning: result)
    }
}
