struct Counter { value: i32 }
impl Counter {
    fn run(&self, limit: i32) -> i32 {
        let mut value = 0;
        while value < limit {
            if value == 2 { value += 1; continue; }
            if value == 5 { break; }
            value += 1;
        }
        return value;
    }
}
fn helper(x: i32) -> i32 { return x + 1; }
fn caller() -> i32 { return helper(3); }
