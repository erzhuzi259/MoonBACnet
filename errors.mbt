///|
pub suberror BacnetError {
  Invalid(String, Int32)
  Unsupported(String)
  Limit(String)
  State(String)
  Property(UInt32, UInt32)
} derive(Debug)

///|
pub(all) struct Limits {
  max_bytes : Int32
  max_nodes : Int32
  max_depth : Int32
  max_objects : Int32
  max_properties : Int32
  max_subscriptions : Int32
  max_pending : Int32
} derive(Debug, Eq)

///|
pub fn Limits::default() -> Limits {
  {
    max_bytes: 65535,
    max_nodes: 8192,
    max_depth: 32,
    max_objects: 256,
    max_properties: 256,
    max_subscriptions: 128,
    max_pending: 128,
  }
}

///|
pub fn Limits::validate(self : Limits) -> Unit raise BacnetError {
  if self.max_bytes < 64 ||
    self.max_bytes > 16777216 ||
    self.max_nodes < 1 ||
    self.max_nodes > 1048576 ||
    self.max_depth < 1 ||
    self.max_depth > 128 ||
    self.max_objects < 1 ||
    self.max_objects > 65536 ||
    self.max_properties < 1 ||
    self.max_properties > 65536 ||
    self.max_subscriptions < 1 ||
    self.max_subscriptions > 65536 ||
    self.max_pending < 1 ||
    self.max_pending > 65536 {
    raise Limit("invalid resource limits")
  }
}

///|
fn require_range(
  value : Int32,
  low : Int32,
  high : Int32,
  name : String,
) -> Unit raise BacnetError {
  if value < low || value > high {
    raise Invalid(name, 0)
  }
}

///|
pub extend BacnetError with @debug.Debug::{to_repr}

///|
pub extend Limits with @debug.Debug::{to_repr}

///|
pub extend Limits with Eq::{equal, not_equal}
