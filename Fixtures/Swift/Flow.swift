struct Counter {
    func run(_ limit: Int) -> Int {
        var value = 0
        while value < limit {
            if value == 2 { value += 1; continue }
            if value == 5 { break }
            value += 1
        }
        guard value > 0 else { return 0 }
        return value
    }
}
func helper(_ x: Int) -> Int { return x + 1 }
func caller() -> Int { return helper(3) }
