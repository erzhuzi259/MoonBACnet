///|
pub(all) struct ReadAccess {
  object : ObjectId
  properties : Array[(UInt32, UInt32?)]
} derive(Debug)

///|
pub(all) enum ReadResult {
  PropertyData(PropertyRef, Array[Tag])
  PropertyFailure(PropertyRef, UInt32, UInt32)
} derive(Debug)

///|
pub(all) struct ReadAccessResult {
  object : ObjectId
  results : Array[ReadResult]
} derive(Debug)

///|
pub fn encode_read_multiple(
  access : Array[ReadAccess],
  limits~ : Limits = Limits::default(),
) -> Bytes raise BacnetError {
  let tags : Array[Tag] = []
  if access.is_empty() {
    raise Invalid("empty read access list", 0)
  }
  for entry in access {
    if entry.properties.is_empty() {
      raise Invalid("empty property references", 0)
    }
    let children : Array[Tag] = []
    for (property, index) in entry.properties {
      children.push(context_uint(0, property))
      if index is Some(i) {
        children.push(context_uint(1, i))
      }
    }
    tags.push(context_object(0, entry.object))
    tags.push(Constructed(1, children))
  }
  encode_tags(tags, limits~)
}

///|
pub fn decode_read_multiple(
  bytes : Bytes,
  limits~ : Limits = Limits::default(),
) -> Array[ReadAccess] raise BacnetError {
  let f = Fields::new(decode_tags(bytes, limits~))
  let result : Array[ReadAccess] = []
  while f.pos < f.tags.length() {
    let object = f.object(0)
    let children = Fields::new(f.children(1))
    let properties : Array[(UInt32, UInt32?)] = []
    while children.pos < children.tags.length() {
      let property = children.uint(0)
      let index = children.optional_uint(1)
      properties.push((property, index))
    }
    if properties.is_empty() {
      raise Invalid("empty property references", f.pos)
    }
    result.push({ object, properties, })
  }
  if result.is_empty() {
    raise Invalid("empty read access list", 0)
  }
  result
}

///|
pub fn encode_multiple_ack(
  access : Array[ReadAccessResult],
  limits~ : Limits = Limits::default(),
) -> Bytes raise BacnetError {
  let tags : Array[Tag] = []
  if access.is_empty() {
    raise Invalid("empty access results", 0)
  }
  for entry in access {
    let children : Array[Tag] = []
    for result in entry.results {
      let (reference, choice) = match result {
        PropertyData(reference, value) => {
          if value.is_empty() {
            raise Invalid("empty access value", 0)
          }
          (reference, Constructed(4, value))
        }
        PropertyFailure(reference, class, code) =>
          (
            reference,
            Constructed(5, [
              Application(Enumerated(class)),
              Application(Enumerated(code)),
            ]),
          )
      }
      if reference.object != entry.object {
        raise Invalid("access object mismatch", 0)
      }
      children.push(context_uint(2, reference.property))
      if reference.index is Some(index) {
        children.push(context_uint(3, index))
      }
      children.push(choice)
    }
    if children.is_empty() {
      raise Invalid("empty result list", 0)
    }
    tags.push(context_object(0, entry.object))
    tags.push(Constructed(1, children))
  }
  encode_tags(tags, limits~)
}

///|
pub fn decode_multiple_ack(
  bytes : Bytes,
  limits~ : Limits = Limits::default(),
) -> Array[ReadAccessResult] raise BacnetError {
  let f = Fields::new(decode_tags(bytes, limits~))
  let output : Array[ReadAccessResult] = []
  while f.pos < f.tags.length() {
    let object = f.object(0)
    let children = Fields::new(f.children(1))
    let results : Array[ReadResult] = []
    while children.pos < children.tags.length() {
      let property = children.uint(2)
      let index = children.optional_uint(3)
      let reference : PropertyRef = { object, property, index, }
      match children.next() {
        Constructed(4, value) => {
          if value.is_empty() {
            raise Invalid("empty access value", children.pos)
          }
          results.push(PropertyData(reference, value))
        }
        Constructed(5, error) =>
          match error[:] {
            [Application(Enumerated(class)), Application(Enumerated(code))] =>
              results.push(PropertyFailure(reference, class, code))
            _ => raise Invalid("property access error fields", children.pos)
          }
        _ => raise Invalid("property access result choice", children.pos)
      }
    }
    if results.is_empty() {
      raise Invalid("empty result list", f.pos)
    }
    output.push({ object, results, })
  }
  if output.is_empty() {
    raise Invalid("empty access results", 0)
  }
  output
}

///|
pub extend ReadAccess with @debug.Debug::{to_repr}

///|
pub extend ReadResult with @debug.Debug::{to_repr}

///|
pub extend ReadAccessResult with @debug.Debug::{to_repr}
