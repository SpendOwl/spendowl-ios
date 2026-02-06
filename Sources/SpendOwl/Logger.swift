//
//  Logger.swift
//  SpendOwl
//
//  Copyright (c) 2024-2026 SpendOwl. All rights reserved.
//  Licensed under the MIT License.
//

import Foundation

/// Logger for the SpendOwl SDK.
///
/// Use ``SpendOwl/logLevel`` to control verbosity. The ``Level`` type
/// is public so it can be used with ``SpendOwl/logLevel``.
public enum Logger {
    /// Log levels for controlling output verbosity.
    public enum Level: Int, Comparable, Sendable {
        /// No logging.
        case none = 0

        /// Only error messages.
        case error = 1

        /// Errors and important informational messages.
        case info = 2

        /// All messages including detailed debug information.
        case debug = 3

        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// The current log level. Defaults to `.none`.
    static var level: Level = .none

    /// Logs a message if the specified level is at or above the current threshold.
    static func log(_ message: @autoclosure () -> String, level: Level) {
        guard level <= self.level else { return }

        #if DEBUG
            let prefix: String
            switch level {
            case .none:
                return
            case .error:
                prefix = "[SpendOwl] ERROR"
            case .info:
                prefix = "[SpendOwl] INFO"
            case .debug:
                prefix = "[SpendOwl] DEBUG"
            }
            // swiftlint:disable:next no_print_statements
            Swift.print("\(prefix) \(message())")
        #endif
    }
}
