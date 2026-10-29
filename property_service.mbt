///|
pub(all) struct PropertyRef {
  object : ObjectId
  property : UInt32
  index : UInt32?
} derive(Debug, Eq)

///|
pub(all) struct PropertyValue {
  reference : PropertyRef
  value : Array[Tag]
} derive(Debug)

///|
pub(all) struct WriteProperty {
  reference : PropertyRef
  value : Array[Tag]
  priority : Int32?
} derive(Debug)

///|
fn reference_tags(reference : PropertyRef) -> Array[Tag] raise BacnetError {
  let tags = [
    context_object(0, reference.object),
    context_uint(1, reference.property),
  ]
  if reference.index is Some(index) {
    tags.push(context_uint(2, index))
  }
  tags
}

///|
fn read_reference(f : Fields) -> PropertyRef raise BacnetError {
  let object = f.object(0)
  let property = f.uint(1)
  let index = f.optional_uint(2)
  { object, property, index, }
}

///|
pub fn encode_read_property(
  reference : PropertyRef,
  limits~ : Limits = Limits::default(),
) -> Bytes raise BacnetError {
  encode_tags(reference_tags(reference), limits~)
}

///|
pub fn decode_read_property(
  bytes : Bytes,
  limits~ : Limits = Limits::default(),
) -> PropertyRef raise BacnetError {
  let f = Fields::new(decode_tags(bytes, limits~))
  let result = read_reference(f)
  f.done()
  result
}

///|
pub fn encode_property_ack(
  ack : PropertyValue,
  limits~ : Limits = Limits::default(),
) -> Bytes raise BacnetError {
  let tags = reference_tags(ack.reference)
  tags.push(Constructed(3, ack.value))
  encode_tags(tags, limits~)
}

///|
pub fn decode_property_ack(
  bytes : Bytes,
  limits~ : Limits = Limits::default(),
) -> PropertyValue raise BacnetError {
  let f = Fields::new(decode_tags(bytes, limits~))
  let reference = read_reference(f)
  let value = f.children(3)
  f.done()
  { reference, value, }
}

///|
pub fn encode_write_property(
  request : WriteProperty,
  limits~ : Limits = Limits::default(),
) -> Bytes raise BacnetError {
  let tags = reference_tags(request.reference)
  tags.push(Constructed(3, request.value))
  if request.priority is Some(priority) {
    require_range(priority, 1, 16, "command priority")
    tags.push(context_uint(4, priority.reinterpret_as_uint()))
  }
  encode_tags(tags, limits~)
}

///|
pub fn decode_write_property(
  bytes : Bytes,
  limits~ : Limits = Limits::default(),
) -> WriteProperty raise BacnetError {
  let f = Fields::new(decode_tags(bytes, limits~))
  let reference = read_reference(f)
  let value = f.children(3)
  let priority = match f.optional_uint(4) {
    Some(n) => {
      if n < 1U || n > 16U {
        raise Invalid("command priority", f.pos)
      }
      Some(n.reinterpret_as_int())
    }
    None => None
  }
  f.done()
  { reference, value, priority, }
}

///|
pub fn encode_error(class : UInt32, code : UInt32) -> Bytes raise BacnetError {
  encode_tags([Application(Enumerated(class)), Application(Enumerated(code))])
}

///|
pub fn decode_error(bytes : Bytes) -> (UInt32, UInt32) raise BacnetError {
  match decode_tags(bytes)[:] {
    [Application(Enumerated(class)), Application(Enumerated(code))] =>
      (class, code)
    _ => raise Invalid("error class and code", 0)
  }
}

///|
pub extend PropertyRef with @debug.Debug::{to_repr}

///|
pub extend PropertyRef with Eq::{equal, not_equal}

///|
pub extend PropertyValue with @debug.Debug::{to_repr}

///|
pub extend WriteProperty with @debug.Debug::{to_repr}
