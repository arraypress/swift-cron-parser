//
//  CronParser+Result.swift
//  SwiftCronParser
//
//  The outcome of parsing a cron expression. Kept nested (`CronParser.Result`) so
//  it does not collide with the standard library's `Swift.Result`.
//
//  Created by David Sherlock on 7/9/26.
//

import Foundation

public extension CronParser {

    /// The result of ``CronParser/parse(_:now:calendar:)``.
    struct Result {

        /// The five parsed fields as `(name, value)` pairs, in order.
        public let fields: [(name: String, value: String)]

        /// A human-readable description, e.g. `"Every 15 minutes."`.
        public let description: String

        /// The next run times (up to 5), in ascending order.
        ///
        /// The scan covers the next 8 years — enough for any satisfiable schedule
        /// (worst case: Feb 29 across a non-leap century year). Empty with a `nil`
        /// ``error`` means the expression parses but never fires.
        public let nextRuns: [Date]

        /// An error message if the expression was invalid, otherwise `nil`.
        public let error: String?

        public init(fields: [(name: String, value: String)], description: String,
                    nextRuns: [Date], error: String?) {
            self.fields = fields
            self.description = description
            self.nextRuns = nextRuns
            self.error = error
        }
    }
}
