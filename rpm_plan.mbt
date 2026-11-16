///|
/// Plan ReadPropertyMultiple request bodies for a discovered unsegmented peer.
/// The peer limit covers the request APDU only, not its reply or BVLC/NPDU.
pub fn plan_read_multiple(
  peer : DiscoveredDevice,
  access : Array[ReadAccess],
  limits~ : Limits = Limits::default(),
) -> Array[Bytes] raise BacnetError {
  limits.validate()
  let max_apdu = peer.announcement.max_apdu
  if max_apdu < 50U || max_apdu > 1476U || access.is_empty() {
    raise Invalid("RPM peer APDU limit or empty access", 0)
  }
  let max_body = max_apdu.reinterpret_as_int() - 4
  let output : Array[Bytes] = []
  let mut batch : Array[ReadAccess] = []
  let mut wire = b""
  let mut total = 0
  for entry in access {
    if entry.properties.is_empty() {
      raise Invalid("empty property references", 0)
    }
    let mut group : Array[(UInt32, UInt32?)] = []
    for property in entry.properties {
      group.push(property)
      let candidate = batch + [{ object: entry.object, properties: group, }]
      let candidate_wire = Some(encode_read_multiple(candidate, limits~)) catch {
        Limit(_) => None
        error => raise error
      }
      if candidate_wire is Some(encoded) && encoded.length() <= max_body {
        wire = encoded
      } else {
        if wire.is_empty() {
          raise Limit("one RPM property exceeds a local or peer APDU limit")
        }
        if output.length() >= limits.max_pending ||
          wire.length() > limits.max_bytes - total {
          raise Limit("RPM plan budget")
        }
        output.push(wire)
        total += wire.length()
        batch = []
        group = [property]
        wire = encode_read_multiple(
          [{ object: entry.object, properties: group, }],
          limits~,
        )
        if wire.length() > max_body {
          raise Limit("one RPM property exceeds peer APDU")
        }
      }
    }
    batch.push({ object: entry.object, properties: group, })
  }
  if output.length() >= limits.max_pending ||
    wire.length() > limits.max_bytes - total {
    raise Limit("RPM plan budget")
  }
  output.push(wire)
  output
}
