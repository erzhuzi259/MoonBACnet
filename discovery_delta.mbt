///|
pub(all) struct DiscoveryDelta {
  added : Array[DiscoveredDevice]
  removed : Array[DiscoveredDevice]
  changed : Array[(DiscoveredDevice, DiscoveredDevice)]
}

///|
fn discovery_index(
  entries : Array[DiscoveredDevice],
  maximum : Int32,
) -> Map[String, DiscoveredDevice] raise BacnetError {
  if maximum < 1 || maximum > 65536 || entries.length() > maximum {
    raise Limit("discovery diff capacity")
  }
  let result : Map[String, DiscoveredDevice] = Map([])
  for e in entries {
    ignore(encode_i_am(e.announcement))
    if e.first_seen > e.last_seen ||
      e.peer.is_empty() ||
      @utf8.encode(e.peer).length() > 256 {
      raise State("invalid discovery snapshot")
    }
    let key = e.announcement.device.instance.to_string()
    if result.contains(key) {
      raise State("duplicate discovered identity")
    }
    result[key] = e
  }
  result
}

///|
/// Ignore timestamp-only refreshes. Preserve source order; never authenticate peers.
pub fn discovery_delta(
  before : Array[DiscoveredDevice],
  after : Array[DiscoveredDevice],
  maximum~ : Int32 = 256,
) -> DiscoveryDelta raise BacnetError {
  let old = discovery_index(before, maximum)
  let next = discovery_index(after, maximum)
  let added : Array[DiscoveredDevice] = []
  let removed : Array[DiscoveredDevice] = []
  let changed : Array[(DiscoveredDevice, DiscoveredDevice)] = []
  for e in after {
    match old.get(e.announcement.device.instance.to_string()) {
      None => added.push(e)
      Some(p) => {
        let a = p.announcement
        let b = e.announcement
        if p.peer != e.peer ||
          a.max_apdu != b.max_apdu ||
          a.vendor != b.vendor ||
          a.segmentation != b.segmentation {
          changed.push((p, e))
        }
      }
    }
  }
  for e in before {
    if !next.contains(e.announcement.device.instance.to_string()) {
      removed.push(e)
    }
  }
  { added, removed, changed, }
}
