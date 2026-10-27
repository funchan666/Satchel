# Satchel

A local-first SwiftUI travel journal and packing companion. The Xcode project is `Satchel.xcodeproj`; `project.yml` is its XcodeGen source.

## Project materials

- `ProjectMaterials/DesignReferences`: reference designs and notes.
- `ProjectMaterials/UIAssets`: original generated Satchel artwork and source images.
- `ProjectMaterials/ContentImages`, `ProjectMaterials/ContentVideos`: optional supplied content.

Only `Satchel/Assets.xcassets` and `Satchel/Resources` are configured as app resources. The material folders are not included in the app target. The original artwork was created using the host-native image tool for this project, including the travel cover, sign-in scene, satchel illustration, paper ticket, app icon, and navigation illustrations.

## Online service

The app presents a sign-in screen with links to both in-app WebView documents. Sign-in requires explicit agreement, retrieves the public IPv4 address and calls the provider’s tourist-login endpoint. The optional online service has a user-visible entry in Me. When opened, the app requests `getV2`; `NB02` supplies the H5 URL. No fixed H5 host list is required. Browsing permits HTTP or HTTPS addresses; calls to native capabilities are restricted to the HTTPS origin initially supplied by the provider. App Transport Security may block insecure HTTP content. `subscription.getStatus` calls the provider's user endpoint. H5 subscription purchasing, product query and restoration remain explicitly unavailable pending the provider's payment integration. Bridge calls check main-frame origin, HTTPS, port, request ID, version and parameters.

Configure `PortalConfiguration.baseURLString` in `Satchel/Sources/Services/PortalBackend.swift` using the real provider API domain. The documents do not contain an actual API domain; `xxx` values are examples. `releaseName` currently uses the iOS example `iaptest.ios` as requested. Placeholder `xxx` addresses in the provider document are not usable endpoints. The app does not route users based on review identity; its online service must be accurately disclosed and accessible during review.

Google Mobile Ads and User Messaging Platform are declared as Swift packages. The sample application ID and official iOS test rewarded ad unit are used. Reward is reported only when the SDK issues its reward callback. AdMob production app ID, production ad unit, SKAdNetwork configuration, privacy messages, and associated disclosure must be completed and validated before release.

## Membership

The intended auto-renewable product IDs are `satchel.plus.monthly` and `satchel.plus.yearly`. Configure them in one subscription group in App Store Connect at USD 9.99/month and USD 99.99/year; the app displays the price returned by the App Store. A-side membership is independent of the provider's H5 payments. The free plan allows 3 trips and 30 photos; active members have unlimited trips and photos. Existing records remain viewable and exportable after expiry. The export is JSON with Base64-encoded local photos; an import workflow is not implemented.

The development bundle identifier is a placeholder. Select the real bundle identifier and signing team before distribution. Supply the operator’s contact details, confirm the online provider’s data-retention and account-deletion process, and publish a privacy policy before release. The app contains local English terms and privacy policy drafts displayed in WebView; these need review and final publication.

## Storage and verification

Journal data and photos are stored in the app's local application-support directory. Removing the app may remove those records. Sign-in uses a Keychain device identifier and a session token held in memory. Since the API base URL is not configured, sign-in is not currently usable. No backend or WebView connection has been verified without the real endpoints.

The project and resource references were inspected statically. No package resolution, build, tests, simulator, device, purchase, advertising, WebView, backend, accessibility, localization-layout, or Duo posture validation has been run. Source inspection does not establish that these flows work at runtime.
