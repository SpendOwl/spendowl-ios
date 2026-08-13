//
//  Version.swift
//  SpendOwl
//
//  Copyright (c) 2024-2026 SpendOwl. All rights reserved.
//  Licensed under the MIT License.
//

/// Single source of truth for the SDK version.
///
/// Update this value in the release PR, together with `CHANGELOG.md`. The `Version
/// matches tag` CI job fails the release if this drifts from the `v`-prefixed git tag,
/// because this string is reported to the backend as `sdkVersion`.
let spendOwlVersion = "1.3.1"
