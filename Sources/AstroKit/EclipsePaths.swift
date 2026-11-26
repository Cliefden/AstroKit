import Foundation

extension MoonCalculator {
    /// The central line of a total, annular or hybrid solar eclipse, sampled
    /// about every 8 minutes from the NASA GSFC Eclipse Web Site path tables
    /// (public domain). Draw the path band around these points.
    public struct EclipsePath: Sendable, Hashable, Identifiable {
        public struct Point: Sendable, Hashable {
            public let latitude: Double
            public let longitude: Double
        }

        /// "YYYY-MM-DD", the UTC day of greatest eclipse.
        public var id: String { String(format: "%04d-%02d-%02d", year, month, day) }
        /// `.solarTotal`, `.solarAnnular` or `.solarHybrid`.
        public let type: EclipseEvent.EclipseType
        public let year: Int
        public let month: Int
        public let day: Int
        /// West-to-east along the central line.
        public let centralLine: [Point]

        /// Every path in the table, in date order.
        public static let all: [EclipsePath] = [
            EclipsePath(type: .solarTotal, year: 2026, month: 8, day: 12, centralLine: [
                .init(latitude: 86.8, longitude: -1.6), .init(latitude: 83.9, longitude: -21.2), .init(latitude: 81.1, longitude: -26.0),
                .init(latitude: 78.5, longitude: -27.5), .init(latitude: 76.0, longitude: -27.9), .init(latitude: 73.7, longitude: -27.8),
                .init(latitude: 71.5, longitude: -27.4), .init(latitude: 69.3, longitude: -26.8), .init(latitude: 67.2, longitude: -26.0),
                .init(latitude: 65.2, longitude: -25.2), .init(latitude: 63.2, longitude: -24.3), .init(latitude: 61.2, longitude: -23.3),
                .init(latitude: 59.2, longitude: -22.2), .init(latitude: 57.3, longitude: -20.9), .init(latitude: 55.3, longitude: -19.6),
                .init(latitude: 53.4, longitude: -18.1), .init(latitude: 51.4, longitude: -16.3), .init(latitude: 49.3, longitude: -14.2),
                .init(latitude: 47.1, longitude: -11.7), .init(latitude: 44.7, longitude: -8.4), .init(latitude: 41.8, longitude: 3.2),
            ]),
            EclipsePath(type: .solarAnnular, year: 2027, month: 2, day: 6, centralLine: [
                .init(latitude: -41.3, longitude: -122.8), .init(latitude: -44.6, longitude: -105.0), .init(latitude: -45.3, longitude: -95.1),
                .init(latitude: -45.3, longitude: -87.5), .init(latitude: -44.8, longitude: -81.3), .init(latitude: -44.0, longitude: -76.0),
                .init(latitude: -43.1, longitude: -71.5), .init(latitude: -41.9, longitude: -67.4), .init(latitude: -40.6, longitude: -63.9),
                .init(latitude: -39.3, longitude: -60.7), .init(latitude: -37.8, longitude: -57.8), .init(latitude: -36.2, longitude: -55.2),
                .init(latitude: -34.6, longitude: -52.7), .init(latitude: -33.0, longitude: -50.5), .init(latitude: -31.2, longitude: -48.4),
                .init(latitude: -29.4, longitude: -46.4), .init(latitude: -27.6, longitude: -44.4), .init(latitude: -25.7, longitude: -42.6),
                .init(latitude: -23.7, longitude: -40.7), .init(latitude: -21.7, longitude: -38.8), .init(latitude: -19.6, longitude: -36.9),
                .init(latitude: -17.5, longitude: -34.8), .init(latitude: -15.2, longitude: -32.6), .init(latitude: -12.8, longitude: -30.2),
                .init(latitude: -10.3, longitude: -27.5), .init(latitude: -7.6, longitude: -24.2), .init(latitude: -4.5, longitude: -20.0),
                .init(latitude: -0.9, longitude: -14.1), .init(latitude: 5.1, longitude: 0.1),
            ]),
            EclipsePath(type: .solarTotal, year: 2027, month: 8, day: 2, centralLine: [
                .init(latitude: 30.5, longitude: -36.2), .init(latitude: 34.3, longitude: -19.6), .init(latitude: 35.4, longitude: -10.4),
                .init(latitude: 35.7, longitude: -3.4), .init(latitude: 35.6, longitude: 2.5), .init(latitude: 35.1, longitude: 7.6),
                .init(latitude: 34.3, longitude: 12.0), .init(latitude: 33.4, longitude: 16.0), .init(latitude: 32.2, longitude: 19.7),
                .init(latitude: 31.0, longitude: 23.0), .init(latitude: 29.6, longitude: 26.1), .init(latitude: 28.1, longitude: 29.0),
                .init(latitude: 26.5, longitude: 31.7), .init(latitude: 24.8, longitude: 34.3), .init(latitude: 23.0, longitude: 36.7),
                .init(latitude: 21.1, longitude: 39.2), .init(latitude: 19.1, longitude: 41.6), .init(latitude: 17.0, longitude: 44.0),
                .init(latitude: 14.8, longitude: 46.5), .init(latitude: 12.5, longitude: 49.1), .init(latitude: 10.0, longitude: 51.9),
                .init(latitude: 7.3, longitude: 55.0), .init(latitude: 4.4, longitude: 58.6), .init(latitude: 1.1, longitude: 63.0),
                .init(latitude: -2.8, longitude: 68.9), .init(latitude: -8.3, longitude: 79.5),
            ]),
            EclipsePath(type: .solarAnnular, year: 2028, month: 1, day: 26, centralLine: [
                .init(latitude: 0.1, longitude: -97.4), .init(latitude: -2.8, longitude: -86.4), .init(latitude: -3.8, longitude: -80.4),
                .init(latitude: -4.2, longitude: -75.9), .init(latitude: -4.3, longitude: -72.2), .init(latitude: -4.1, longitude: -69.1),
                .init(latitude: -3.7, longitude: -66.3), .init(latitude: -3.2, longitude: -63.9), .init(latitude: -2.6, longitude: -61.6),
                .init(latitude: -1.8, longitude: -59.6), .init(latitude: -0.9, longitude: -57.6), .init(latitude: 0.1, longitude: -55.8),
                .init(latitude: 1.2, longitude: -54.0), .init(latitude: 2.4, longitude: -52.3), .init(latitude: 3.6, longitude: -50.7),
                .init(latitude: 5.0, longitude: -49.1), .init(latitude: 6.5, longitude: -47.4), .init(latitude: 8.0, longitude: -45.7),
                .init(latitude: 9.7, longitude: -44.0), .init(latitude: 11.5, longitude: -42.2), .init(latitude: 13.4, longitude: -40.3),
                .init(latitude: 15.5, longitude: -38.1), .init(latitude: 17.8, longitude: -35.7), .init(latitude: 20.3, longitude: -33.0),
                .init(latitude: 23.1, longitude: -29.6), .init(latitude: 26.4, longitude: -25.3), .init(latitude: 30.5, longitude: -19.2),
                .init(latitude: 33.2, longitude: -14.5), .init(latitude: 37.5, longitude: -5.8),
            ]),
            EclipsePath(type: .solarTotal, year: 2028, month: 7, day: 22, centralLine: [
                .init(latitude: -15.2, longitude: 84.8), .init(latitude: -12.2, longitude: 95.5), .init(latitude: -11.2, longitude: 101.5),
                .init(latitude: -10.7, longitude: 106.1), .init(latitude: -10.7, longitude: 109.9), .init(latitude: -11.0, longitude: 113.3),
                .init(latitude: -11.5, longitude: 116.2), .init(latitude: -12.2, longitude: 118.9), .init(latitude: -13.1, longitude: 121.5),
                .init(latitude: -14.1, longitude: 123.9), .init(latitude: -15.3, longitude: 126.3), .init(latitude: -16.7, longitude: 128.6),
                .init(latitude: -18.2, longitude: 131.0), .init(latitude: -19.9, longitude: 133.3), .init(latitude: -21.8, longitude: 135.9),
                .init(latitude: -23.9, longitude: 138.5), .init(latitude: -26.3, longitude: 141.5), .init(latitude: -29.1, longitude: 144.9),
                .init(latitude: -34.2, longitude: 151.6), .init(latitude: -42.0, longitude: 163.4),
            ]),
            EclipsePath(type: .solarAnnular, year: 2030, month: 6, day: 1, centralLine: [
                .init(latitude: 29.7, longitude: 3.7), .init(latitude: 38.1, longitude: 22.4), .init(latitude: 41.8, longitude: 29.9),
                .init(latitude: 44.7, longitude: 35.8), .init(latitude: 47.0, longitude: 41.0), .init(latitude: 49.0, longitude: 45.8),
                .init(latitude: 50.8, longitude: 50.5), .init(latitude: 52.3, longitude: 55.1), .init(latitude: 53.5, longitude: 59.7),
                .init(latitude: 54.6, longitude: 64.4), .init(latitude: 55.4, longitude: 69.1), .init(latitude: 56.0, longitude: 74.0),
                .init(latitude: 56.5, longitude: 78.9), .init(latitude: 56.7, longitude: 83.9), .init(latitude: 56.7, longitude: 88.9),
                .init(latitude: 56.4, longitude: 94.0), .init(latitude: 56.0, longitude: 99.2), .init(latitude: 55.3, longitude: 104.4),
                .init(latitude: 54.3, longitude: 109.6), .init(latitude: 53.1, longitude: 114.9), .init(latitude: 51.6, longitude: 120.4),
                .init(latitude: 49.7, longitude: 126.1), .init(latitude: 47.4, longitude: 132.4), .init(latitude: 44.4, longitude: 139.6),
                .init(latitude: 39.8, longitude: 149.9),
            ]),
            EclipsePath(type: .solarTotal, year: 2030, month: 11, day: 25, centralLine: [
                .init(latitude: -18.9, longitude: 8.2), .init(latitude: -25.2, longitude: 22.0), .init(latitude: -28.7, longitude: 29.2),
                .init(latitude: -31.5, longitude: 34.8), .init(latitude: -33.8, longitude: 39.7), .init(latitude: -35.7, longitude: 44.1),
                .init(latitude: -37.5, longitude: 48.2), .init(latitude: -39.0, longitude: 52.3), .init(latitude: -40.3, longitude: 56.2),
                .init(latitude: -41.4, longitude: 60.1), .init(latitude: -42.4, longitude: 64.1), .init(latitude: -43.1, longitude: 68.0),
                .init(latitude: -43.7, longitude: 72.1), .init(latitude: -44.1, longitude: 76.2), .init(latitude: -44.4, longitude: 80.5),
                .init(latitude: -44.4, longitude: 84.9), .init(latitude: -44.2, longitude: 89.4), .init(latitude: -43.8, longitude: 94.1),
                .init(latitude: -43.2, longitude: 99.0), .init(latitude: -42.3, longitude: 104.2), .init(latitude: -41.0, longitude: 109.9),
                .init(latitude: -39.3, longitude: 116.1), .init(latitude: -36.9, longitude: 123.5), .init(latitude: -33.3, longitude: 133.5),
                .init(latitude: -30.0, longitude: 142.0),
            ]),
        ]
    }
}
