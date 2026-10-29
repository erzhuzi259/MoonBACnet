pub suberror BacnetError {
  Invalid(String, Int)
  Unsupported(String)
  Limit(String)
  State(String)
} derive(Debug)

pub(all) struct Limits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_objects : Int
  max_properties : Int
  max_subscriptions : Int
  max_pending : Int
} derive(Debug, Eq)

pub fn Limits::default() -> Limits {
  { max_bytes: 65535, max_nodes: 8192, max_depth: 32,
    max_objects: 256, max_properties: 256, max_subscriptions: 128, max_pending: 128 }
}

pub fn Limits::validate(self : Limits) -> Unit raise BacnetError {
  if self.max_bytes < 64 || self.max_bytes > 16777216 ||
    self.max_nodes < 1 || self.max_nodes > 1048576 ||
    self.max_depth < 1 || self.max_depth > 128 ||
    self.max_objects < 1 || self.max_objects > 65536 ||
    self.max_properties < 1 || self.max_properties > 65536 ||
    self.max_subscriptions < 1 || self.max_subscriptions > 65536 ||
    self.max_pending < 1 || self.max_pending > 65536 {
    raise Limit("invalid resource limits")
  }
}

fn require_range(value : Int, low : Int, high : Int, name : String) -> Unit raise BacnetError {
  if value < low || value > high { raise Invalid(name, 0) }
}

pub extend BacnetError with @debug.Debug::{to_repr}

pub extend Limits with @debug.Debug::{to_repr}

pub extend Limits with Eq::{equal, not_equal}
