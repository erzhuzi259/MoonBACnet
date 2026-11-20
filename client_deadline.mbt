///|
/// Earliest active retry or expiry deadline on the caller's clock.
pub fn Client::next_deadline(self : Client) -> UInt64? {
  let mut next : UInt64? = None
  for request in self.pending {
    let due = request.deadline
    next = Some(next.map(value => value.min(due)).unwrap_or(due))
  }
  next
}
