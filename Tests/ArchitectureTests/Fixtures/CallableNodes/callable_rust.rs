#[derive(Debug)]
pub struct Error;
pub trait CallableService { fn read(&self) -> i32; }
pub struct CallableWorker;

pub fn callable_rust<T>(value: T) -> T { value }

impl CallableWorker {
    pub async unsafe fn update<'a, T>(&'a mut self, value: &'a T) -> Result<&'a T, Error>
    where T: Clone {
        Ok(callable_rust(value))
    }

    pub fn new() -> Self { Self }
    pub fn consume(self) -> Self { self }
    pub fn inspect(&self) {}
    pub fn boxed(self: Box<Self>) -> Self { *self }
}
