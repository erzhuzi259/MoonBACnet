///|
pub(all) struct WhoIs {
  low : Int32?
  high : Int32?
} derive(Debug)

///|
pub(all) struct IAm {
  device : ObjectId
  max_apdu : UInt32
  segmentation : UInt32
  vendor : UInt32
} derive(Debug)

///|
pub fn encode_who_is(
  query : WhoIs,
  limits~ : Limits = Limits::default(),
) -> Bytes raise BacnetError {
  let tags : Array[Tag] = []
  match (query.low, query.high) {
    (None, None) => ()
    (Some(low), Some(high)) => {
      require_range(low, 0, 4194303, "Who-Is low")
      require_range(high, low, 4194303, "Who-Is high")
      tags.push(context_uint(0, low.reinterpret_as_uint()))
      tags.push(context_uint(1, high.reinterpret_as_uint()))
    }
    _ => raise Invalid("Who-Is needs both bounds", 0)
  }
  encode_tags(tags, limits~)
}

///|
pub fn decode_who_is(
  bytes : Bytes,
  limits~ : Limits = Limits::default(),
) -> WhoIs raise BacnetError {
  let f = Fields::new(decode_tags(bytes, limits~))
  if f.tags.is_empty() {
    return { low: None, high: None, }
  }
  let low = f.uint(0)
  let high = f.uint(1)
  f.done()
  if low > high || high > 4194303U {
    raise Invalid("Who-Is bounds", 0)
  }
  {
    low: Some(low.reinterpret_as_int()),
    high: Some(high.reinterpret_as_int()),
  }
}

///|
fn iam_valid(value : IAm) -> Unit raise BacnetError {
  if value.device.kind != 8 ||
    value.max_apdu < 50U ||
    value.max_apdu > 65535U ||
    value.segmentation > 3U ||
    value.vendor > 65535U {
    raise Invalid("I-Am fields", 0)
  }
}

///|
pub fn encode_i_am(
  value : IAm,
  limits~ : Limits = Limits::default(),
) -> Bytes raise BacnetError {
  iam_valid(value)
  encode_tags(
    [
      Application(Object(value.device)),
      Application(Unsigned(value.max_apdu)),
      Application(Enumerated(value.segmentation)),
      Application(Unsigned(value.vendor)),
    ],
    limits~,
  )
}

///|
pub fn decode_i_am(
  bytes : Bytes,
  limits~ : Limits = Limits::default(),
) -> IAm raise BacnetError {
  let tags = decode_tags(bytes, limits~)
  let result : IAm = match tags[:] {
    [
      Application(Object(device)),
      Application(Unsigned(max_apdu)),
      Application(Enumerated(segmentation)),
      Application(Unsigned(vendor)),
    ] => { device, max_apdu, segmentation, vendor, }
    _ => raise Invalid("I-Am sequence", 0)
  }
  iam_valid(result)
  result
}

///|
pub extend WhoIs with @debug.Debug::{to_repr}

///|
pub extend IAm with @debug.Debug::{to_repr}
