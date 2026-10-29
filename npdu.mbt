///|
pub(all) struct Route {
  network : Int32
  address : Bytes
} derive(Debug)

///|
pub(all) struct Npdu {
  destination : Route?
  source : Route?
  hop_count : Int32
  expecting_reply : Bool
  priority : Int32
  payload : Bytes
} derive(Debug)

///|
fn route_valid(route : Route, source : Bool) -> Unit raise BacnetError {
  require_range(
    route.network,
    1,
    if source {
      65534
    } else {
      65535
    },
    "network number",
  )
  if route.address.length() > 255 ||
    (source && route.address.is_empty()) ||
    (route.network == 65535 && !route.address.is_empty()) {
    raise Invalid("route address", 0)
  }
}

///|
fn write_route(
  w : Writer,
  route : Route,
  source : Bool,
) -> Unit raise BacnetError {
  route_valid(route, source)
  w.uint(route.network.reinterpret_as_uint(), 2)
  w.u8(route.address.length())
  w.put(route.address)
}

///|
fn read_route(r : Reader, source : Bool) -> Route raise BacnetError {
  let network = r.uint(2).reinterpret_as_int()
  let address = r.take(r.u8())
  let result : Route = { network, address, }
  route_valid(result, source)
  result
}

///|
pub fn Npdu::for_local(
  payload : Bytes,
  expecting_reply~ : Bool = false,
) -> Npdu {
  {
    destination: None,
    source: None,
    hop_count: 255,
    expecting_reply,
    priority: 0,
    payload,
  }
}

///|
pub fn encode_npdu(
  npdu : Npdu,
  limits~ : Limits = Limits::default(),
) -> Bytes raise BacnetError {
  limits.validate()
  require_range(npdu.priority, 0, 3, "network priority")
  require_range(npdu.hop_count, 0, 255, "hop count")
  let mut control = npdu.priority | (if npdu.expecting_reply { 4 } else { 0 })
  if npdu.destination is Some(_) {
    control = control | 0x20
  }
  if npdu.source is Some(_) {
    control = control | 8
  }
  let w = Writer::new(limits.max_bytes)
  w.u8(1)
  w.u8(control)
  if npdu.destination is Some(route) {
    write_route(w, route, false)
  }
  if npdu.source is Some(route) {
    write_route(w, route, true)
  }
  if npdu.destination is Some(_) {
    w.u8(npdu.hop_count)
  }
  if npdu.payload.is_empty() {
    raise Invalid("missing APDU", 0)
  }
  w.put(npdu.payload)
  w.finish()
}

///|
pub fn decode_npdu(
  data : Bytes,
  limits~ : Limits = Limits::default(),
) -> Npdu raise BacnetError {
  let r = Reader::new(data, limits)
  if r.u8() != 1 {
    raise Unsupported("NPDU version")
  }
  let control = r.u8()
  if (control & 0x50) != 0 {
    raise Invalid("NPDU reserved flags", 1)
  }
  if (control & 0x80) != 0 {
    raise Unsupported("network-layer message")
  }
  let destination = if (control & 0x20) != 0 {
    Some(read_route(r, false))
  } else {
    None
  }
  let source = if (control & 8) != 0 { Some(read_route(r, true)) } else { None }
  let hop_count = if destination is Some(_) { r.u8() } else { 255 }
  let payload = r.take(r.remaining())
  if payload.is_empty() {
    raise Invalid("missing APDU", r.pos)
  }
  {
    destination,
    source,
    hop_count,
    expecting_reply: (control & 4) != 0,
    priority: control & 3,
    payload,
  }
}

///|
pub extend Route with @debug.Debug::{to_repr}

///|
pub extend Npdu with @debug.Debug::{to_repr}
