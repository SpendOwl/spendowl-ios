//
//  AttributionResult.swift
//  SpendOwl
//
//  Copyright (c) 2024-2026 SpendOwl. All rights reserved.
//  Licensed under the MIT License.
//

import Foundation

/// The result of an attribution lookup.
///
/// Contains information about how the user discovered and installed your app,
/// including campaign, ad group, and keyword data from Apple Search Ads.
///
/// ## Example
///
/// ```swift
/// let attribution = try await SpendOwl.attribution()
///
/// switch attribution.status {
/// case .attributed:
///     print("Campaign: \(attribution.campaignName ?? "unknown")")
///     print("Keyword: \(attribution.keyword ?? "unknown")")
///     print("Country: \(attribution.countryOrRegion ?? "unknown")")
/// case .organic:
///     print("User found the app organically")
/// case .unknown:
///     print("Attribution data not yet available")
/// }
/// ```
public struct AttributionResult: Sendable {
    /// A unique identifier for this attribution record.
    public let id: String

    /// The attribution status indicating how the user acquired the app.
    public let status: AttributionStatus

    /// The Apple Search Ads campaign ID.
    ///
    /// Only available when `status` is `.attributed`.
    public let campaignId: Int?

    /// The Apple Search Ads campaign name.
    ///
    /// Only available when `status` is `.attributed`.
    public let campaignName: String?

    /// The ad group ID within the campaign.
    ///
    /// Only available when `status` is `.attributed`.
    public let adGroupId: Int?

    /// The ad group name.
    ///
    /// Only available when `status` is `.attributed`.
    public let adGroupName: String?

    /// The keyword ID that triggered the ad.
    ///
    /// Only available when `status` is `.attributed`.
    public let keywordId: Int?

    /// The keyword text that the user searched for.
    ///
    /// Only available when `status` is `.attributed`.
    public let keyword: String?

    /// The two-letter country or region code (e.g., "US", "GB", "JP").
    ///
    /// Indicates where the ad was shown and the install occurred.
    public let countryOrRegion: String?

    /// The date and time when the user clicked the ad.
    ///
    /// Only available when the user has opted into tracking.
    public let clickDate: Date?

    /// The type of conversion: "Download" for new installs, "Redownload" for reinstalls.
    public let conversionType: String?

    /// The ad placement where the user saw the ad.
    ///
    /// Possible values include:
    /// - `"top_of_search"`: The top position in App Store search results
    /// - `"search_results"`: Other positions in search results
    ///
    /// - Note: Available for installs from March 2026 onwards when Apple
    ///   expands ad placements in the App Store.
    public let supplyPlacement: String?
}

// MARK: - Codable

extension AttributionResult: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case status
        case campaignId
        case campaignName
        case adGroupId
        case adGroupName
        case keywordId
        case keyword
        case countryOrRegion
        case clickDate
        case conversionType
        case supplyPlacement
    }
}

// MARK: - Equatable

extension AttributionResult: Equatable {}

// MARK: - Attribution Status

/// The attribution status indicating how the user acquired the app.
public enum AttributionStatus: String, Sendable {
    /// The user installed the app after clicking an Apple Search Ads advertisement.
    ///
    /// When attributed, the ``AttributionResult`` contains campaign, ad group,
    /// and keyword data.
    case attributed

    /// The user found and installed the app organically (not through ads).
    ///
    /// Organic installs don't have campaign or keyword data.
    case organic

    /// The attribution status could not be determined.
    ///
    /// This may occur when:
    /// - Attribution data is still being processed
    /// - The device doesn't support attribution
    /// - An error occurred during attribution lookup
    case unknown
}

// MARK: - Codable

extension AttributionStatus: Codable {}
