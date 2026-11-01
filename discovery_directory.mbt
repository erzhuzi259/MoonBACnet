///|
pub(all) struct DiscoveredDevice {
  peer : String
  announcement : IAm
  first_seen : UInt64
  last_seen : UInt64
}

///|
pub struct DiscoveryDirectory {
  priv entries : Array[DiscoveredDevice]
  priv maximum : Int32
  priv mut clock : UInt64
}

///|
pub fn DiscoveryDirectory::new(
  maximum~ : Int32 = 256,
) -> DiscoveryDirectory raise BacnetError {
  if maximum <= 0 || maximum > 65536 {
    raise Limit("discovery capacity")
  }
  { entries: [], maximum, clock: 0UL, }
}

///|
/// Observe an already-decoded I-Am. Duplicate device IDs at different peers are
/// conflicts, never silently reassigned. Caller chooses peer/address identity.
pub fn DiscoveryDirectory::observe(
  self : DiscoveryDirectory,
  peer : String,
  announcement : IAm,
  now : UInt64,
) -> Bool raise BacnetError {
  if now < self.clock {
    raise State("discovery clock reversed")
  }
  if peer.is_empty() || @utf8.encode(peer).length() > 256 {
    raise Limit("discovery peer length")
  }
  if announcement.device.kind != 8 ||
    announcement.device.instance == 4194303 ||
    announcement.vendor > 65535U ||
    announcement.max_apdu < 50U ||
    announcement.max_apdu > 1476U ||
    announcement.segmentation > 3U {
    raise Invalid("I-Am capability fields", 0)
  }
  for i, entry in self.entries {
    if entry.announcement.device == announcement.device {
      if entry.peer != peer ||
        entry.announcement.vendor != announcement.vendor ||
        entry.announcement.max_apdu != announcement.max_apdu ||
        entry.announcement.segmentation != announcement.segmentation {
        raise State(
          "conflicting device identity or capabilities; expire or forget explicitly",
        )
      }
      self.entries[i] = { ..entry, last_seen: now, }
      self.clock = now
      return false
    }
  }
  if self.entries.length() >= self.maximum {
    raise Limit("discovery capacity")
  }
  self.entries.push({ peer, announcement, first_seen: now, last_seen: now, })
  self.clock = now
  true
}

///|
pub fn DiscoveryDirectory::devices(
  self : DiscoveryDirectory,
) -> Array[DiscoveredDevice] {
  self.entries.copy()
}

///|
pub fn DiscoveryDirectory::expire(
  self : DiscoveryDirectory,
  now : UInt64,
  max_age : UInt64,
) -> Array[DiscoveredDevice] raise BacnetError {
  if now < self.clock {
    raise State("discovery clock reversed")
  }
  let expired = self.entries.filter(e => now - e.last_seen >= max_age)
  let retained = self.entries.filter(e => now - e.last_seen < max_age)
  self.entries.clear()
  for entry in retained {
    self.entries.push(entry)
  }
  self.clock = now
  expired
}

///|
pub fn DiscoveryDirectory::forget(
  self : DiscoveryDirectory,
  device : ObjectId,
) -> Bool {
  for i, entry in self.entries {
    if entry.announcement.device == device {
      self.entries.remove(i) |> ignore
      return true
    }
  }
  false
}
