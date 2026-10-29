///|
pub(all) struct SubscribeCov {
  process : UInt32
  object : ObjectId
  confirmed : Bool?
  lifetime : UInt32?
} derive(Debug)

///|
pub(all) struct CovProperty {
  property : UInt32
  index : UInt32?
  value : Array[Tag]
  priority : Int32?
} derive(Debug)

///|
pub(all) struct CovNotification {
  process : UInt32
  device : ObjectId
  object : ObjectId
  remaining : UInt32
  values : Array[CovProperty]
} derive(Debug)

///|
pub fn encode_subscribe_cov(
  s : SubscribeCov,
  limits~ : Limits = Limits::default(),
) -> Bytes raise BacnetError {
  let tags = [context_uint(0, s.process), context_object(1, s.object)]
  match (s.confirmed, s.lifetime) {
    (None, None) => ()
    (Some(confirmed), Some(lifetime)) => {
      tags.push(context_bool(2, confirmed))
      tags.push(context_uint(3, lifetime))
    }
    _ => raise Invalid("COV cancellation needs both fields absent", 0)
  }
  encode_tags(tags, limits~)
}

///|
pub fn decode_subscribe_cov(
  bytes : Bytes,
  limits~ : Limits = Limits::default(),
) -> SubscribeCov raise BacnetError {
  let f = Fields::new(decode_tags(bytes, limits~))
  let process = f.uint(0)
  let object = f.object(1)
  let confirmed = match f.optional(2) {
    Some(b) => Some(read_context_bool(b))
    None => None
  }
  let lifetime = f.optional_uint(3)
  f.done()
  let result : SubscribeCov = { process, object, confirmed, lifetime, }
  ignore(encode_subscribe_cov(result, limits~))
  result
}

///|
pub fn encode_cov(
  notification : CovNotification,
  limits~ : Limits = Limits::default(),
) -> Bytes raise BacnetError {
  if notification.device.kind != 8 || notification.values.is_empty() {
    raise Invalid("COV device or values", 0)
  }
  let values : Array[Tag] = []
  for entry in notification.values {
    values.push(context_uint(0, entry.property))
    if entry.index is Some(index) {
      values.push(context_uint(1, index))
    }
    if entry.value.is_empty() {
      raise Invalid("empty COV value", 0)
    }
    values.push(Constructed(2, entry.value))
    if entry.priority is Some(priority) {
      require_range(priority, 1, 16, "COV priority")
      values.push(context_uint(3, priority.reinterpret_as_uint()))
    }
  }
  encode_tags(
    [
      context_uint(0, notification.process),
      context_object(1, notification.device),
      context_object(2, notification.object),
      context_uint(3, notification.remaining),
      Constructed(4, values),
    ],
    limits~,
  )
}

///|
pub fn decode_cov(
  bytes : Bytes,
  limits~ : Limits = Limits::default(),
) -> CovNotification raise BacnetError {
  let f = Fields::new(decode_tags(bytes, limits~))
  let process = f.uint(0)
  let device = f.object(1)
  let object = f.object(2)
  let remaining = f.uint(3)
  let entries = Fields::new(f.children(4))
  f.done()
  let values : Array[CovProperty] = []
  while entries.pos < entries.tags.length() {
    let property = entries.uint(0)
    let index = entries.optional_uint(1)
    let value = entries.children(2)
    let priority = match entries.optional_uint(3) {
      Some(p) => {
        if p < 1U || p > 16U {
          raise Invalid("COV priority", entries.pos)
        }
        Some(p.reinterpret_as_int())
      }
      None => None
    }
    values.push({ property, index, value, priority, })
  }
  let result : CovNotification = { process, device, object, remaining, values, }
  ignore(encode_cov(result, limits~))
  result
}

///|
pub extend SubscribeCov with @debug.Debug::{to_repr}

///|
pub extend CovProperty with @debug.Debug::{to_repr}

///|
pub extend CovNotification with @debug.Debug::{to_repr}
