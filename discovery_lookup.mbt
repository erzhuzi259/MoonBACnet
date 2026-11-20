///|
/// Look up a device without advancing the directory clock or purging entries.
pub fn DiscoveryDirectory::lookup(
  self : DiscoveryDirectory,
  device : ObjectId,
  now : UInt64,
  max_age~ : UInt64? = None,
) -> DiscoveredDevice? raise BacnetError {
  if now < self.clock {
    raise State("discovery clock reversed")
  }
  for entry in self.entries {
    if entry.announcement.device == device {
      if max_age is Some(age) && now - entry.last_seen >= age {
        return None
      }
      return Some(entry)
    }
  }
  None
}
