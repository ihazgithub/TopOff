import Foundation

/// When TopOff first saw a package's pending version: the moment the
/// release cooldown counts from.
struct FirstSeenVersion: Codable, Equatable {
    let version: String
    let date: Date
}

/// Optional wait before TopOff offers a new version of a package. Bad and
/// compromised releases are usually caught and pulled within days, so
/// waiting until a version has been out for a while lets somebody else
/// find the problem first.
///
/// A version's age counts from the first check that listed it as
/// outdated. A check can only list a version that is already out, so this
/// never overstates its age, and it needs nothing beyond `brew outdated`.
/// The cost is a late start when TopOff wasn't checking: a version that
/// came out while the Mac was off, or before this feature shipped, waits
/// the full cooldown from the first check that saw it.
enum ReleaseCooldown {

    /// Day counts offered under Options. 0, the default, turns the cooldown off.
    static let dayChoices = [0, 3, 7, 10, 14]

    static let daysUserDefaultsKey = "releaseCooldownDays"

    /// The saved day count, or 0 (off) when there is none or it isn't one
    /// of `dayChoices`, such as a count a later version saved.
    static func storedDays(in defaults: UserDefaults = .standard) -> Int {
        let days = defaults.integer(forKey: daysUserDefaultsKey)
        return dayChoices.contains(days) ? days : 0
    }

    /// Which packages the cooldown holds back. Casks download the vendor's
    /// own app, which Homebrew's review can't vouch for, so they gain the
    /// most from waiting. Formulae are reviewed and built by Homebrew, and
    /// holding them back would also delay urgent fixes such as OpenSSL's.
    enum Scope: String {
        case casksOnly
        case allPackages

        static let userDefaultsKey = "releaseCooldownScope"

        /// The saved scope, or casks only when there is none or it isn't
        /// one this version knows, such as one a later version saved.
        static func stored(in defaults: UserDefaults = .standard) -> Scope {
            guard let rawValue = defaults.string(forKey: userDefaultsKey),
                  let scope = Scope(rawValue: rawValue) else {
                return .casksOnly
            }

            return scope
        }

        func save(in defaults: UserDefaults = .standard) {
            defaults.set(rawValue, forKey: Self.userDefaultsKey)
        }
    }

    /// Records when each of `packages` was first seen at its pending
    /// version, after a check that listed them. A package keeps its date
    /// for as long as its pending version stays the same; a newer version
    /// starts again from `now`.
    ///
    /// Only a greedy check lists every outdated cask, so only a greedy
    /// check forgets packages it didn't list. A regular check leaves out
    /// casks that update themselves, and forgetting those would restart
    /// their cooldown each time Update All (Greedy) listed them again.
    static func firstSeenVersions(
        after packages: [OutdatedPackage],
        previous: [String: FirstSeenVersion],
        greedyCheck: Bool,
        now: Date = Date()
    ) -> [String: FirstSeenVersion] {
        var firstSeen = greedyCheck ? [:] : previous
        for package in packages {
            if let seen = previous[package.name], seen.version == package.latestVersion {
                firstSeen[package.name] = seen
            } else {
                firstSeen[package.name] = FirstSeenVersion(version: package.latestVersion, date: now)
            }
        }
        return firstSeen
    }

    /// Whole days, rounded up, until `package`'s pending version has been
    /// known for `cooldownDays` days, or nil once it has, while the cooldown is
    /// off, or when `scope` leaves the package out. A version with no record
    /// counts as first seen `now`.
    ///
    /// A package of unknown kind counts as a cask, so when unsure it waits.
    /// Letting a cask through early would skip the very downloads the cooldown
    /// is for, while holding back a formula only delays it, and Update Now
    /// is there for that.
    static func daysRemaining(
        for package: OutdatedPackage,
        cooldownDays: Int,
        scope: Scope,
        firstSeen: [String: FirstSeenVersion],
        now: Date = Date()
    ) -> Int? {
        guard cooldownDays > 0 else { return nil }
        if scope == .casksOnly && package.kind == .formula { return nil }

        var seenDate = now
        if let seen = firstSeen[package.name], seen.version == package.latestVersion {
            // A date after `now` (the clock was set back) counts as now, so
            // the wait never runs past the cooldown.
            seenDate = min(seen.date, now)
        }

        let readyDate = seenDate.addingTimeInterval(TimeInterval(cooldownDays) * secondsPerDay)
        let remaining = readyDate.timeIntervalSince(now)
        guard remaining > 0 else { return nil }
        return Int((remaining / secondsPerDay).rounded(.up))
    }

    /// "1 day", "3 days": how long a package has left in the cooldown, as
    /// the menu and the Outdated Packages window say it.
    static func dayCount(_ days: Int) -> String {
        "\(days) day\(days == 1 ? "" : "s")"
    }

    private static let secondsPerDay: TimeInterval = 86_400
}
