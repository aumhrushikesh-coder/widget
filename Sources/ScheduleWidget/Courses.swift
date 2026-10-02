import Foundation

/// A course from the term's course list. `key` is the section-course prefix the timetable
/// cells start with (e.g. "S5-C1" in "S5-C1-TBFS:MMP (Taral P) (7)").
struct Course: Hashable {
    let key: String
    let code: String
    let name: String
    let faculty: String
    let credits: Int
    let track: String
    let colorIndex: Int
}

enum CourseCatalog {
    static let known: [Course] = [
        Course(key: "S5-C1", code: "TBFS:MMP", name: "The Business of Financial Services: Markets, Models and Products",
               faculty: "Taral Pathak, Hemal Vakil, Puneet Kapoor, Deepak Krishnan", credits: 3, track: "BFSI & FinTech", colorIndex: 0),
        Course(key: "S5-C3", code: "TFE:PPI", name: "The FinTech Ecosystem: Platforms, Policy and Inclusion",
               faculty: "Amit Saraswat", credits: 2, track: "BFSI & FinTech", colorIndex: 1),
        Course(key: "S5-C4", code: "CMAVRA", name: "Capital Markets Architecture: Valuation, Risk and Analysis (Projects)",
               faculty: "Taral Pathak, Deepak Krishnan", credits: 2, track: "BFSI & FinTech", colorIndex: 2),
        Course(key: "S8-C1", code: "LOS", name: "Language of the Sector",
               faculty: "Vivek Ganotra", credits: 1, track: "Consulting & Tech Consulting", colorIndex: 3),
        Course(key: "S8-C2", code: "BOS", name: "Business of the Sector",
               faculty: "Gayathri Parthasarathy", credits: 2, track: "Consulting & Tech Consulting", colorIndex: 4),
        Course(key: "S8-C3", code: "SLDS", name: "Sectoral Legacy and Disruptive Startups",
               faculty: "Sam Evans, Sudipta Ghosh", credits: 2, track: "Consulting & Tech Consulting", colorIndex: 5),
        Course(key: "S8-C4", code: "PRGOS", name: "Policy, Regulation, and Geopolitics of the Sector",
               faculty: "Anil Vaidya", credits: 2, track: "Consulting & Tech Consulting", colorIndex: 6),
    ]

    static let defaultKeys = known.map(\.key)

    /// Reduces whatever the user typed ("S5-C1-TBFS:MMP", "s5 c1", "S5") to the prefix used for matching.
    static func key(for typed: String) -> String {
        let upper = typed.uppercased().trimmingCharacters(in: .whitespaces)
        let tokens = upper.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        if tokens.count >= 2,
           tokens[0].range(of: "^[A-Z]+\\d+$", options: .regularExpression) != nil,
           tokens[1].range(of: "^[A-Z]+\\d+$", options: .regularExpression) != nil {
            return "\(tokens[0])-\(tokens[1])"
        }
        return tokens.first ?? upper
    }

    static func course(for key: String) -> Course? {
        known.first { $0.key == key }
    }
}
