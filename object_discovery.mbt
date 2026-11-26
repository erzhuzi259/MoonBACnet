///|
#derive(Debug, Eq)
pub(all) enum ObjectQuery {
  Identifier(ObjectId)
  Name(String)
}

///|
#derive(Debug)
pub(all) struct WhoHas {
  range : WhoIs
  object : ObjectQuery
}

///|
#derive(Debug)
pub(all) struct IHave {
  device : ObjectId
  object : ObjectId
  name : String
}

///|
pub fn encode_who_has(
  query : WhoHas,
  limits~ : Limits = Limits::default(),
) -> Bytes raise BacnetError {
  let tags = decode_tags(encode_who_is(query.range, limits~), limits~)
  tags.push(
    match query.object {
      Identifier(id) => context_object(2, id)
      Name(name) => {
        let (kind, bytes) = application_body(Text(name), limits)
        ignore(kind)
        Context(3, bytes)
      }
    },
  )
  encode_tags(tags, limits~)
}

///|
pub fn decode_who_has(
  bytes : Bytes,
  limits~ : Limits = Limits::default(),
) -> WhoHas raise BacnetError {
  let fields = Fields::new(decode_tags(bytes, limits~))
  let low = fields.optional_uint(0)
  let high = fields.optional_uint(1)
  let range : WhoIs = match (low, high) {
    (None, None) => { low: None, high: None, }
    (Some(a), Some(b)) if a <= b && b <= 4194303U =>
      { low: Some(a.reinterpret_as_int()), high: Some(b.reinterpret_as_int()), }
    _ => raise Invalid("Who-Has device range", 0)
  }
  let object = match fields.next() {
    Context(2, data) if data.length() == 4 =>
      Identifier(ObjectId::from_number(read_unsigned(data)))
    Context(3, data) =>
      match application_value(7, data, limits) {
        Text(name) => Name(name)
        _ => raise Invalid("Who-Has name", fields.pos)
      }
    _ => raise Invalid("Who-Has object choice", fields.pos)
  }
  fields.done()
  { range, object, }
}

///|
pub fn encode_i_have(
  value : IHave,
  limits~ : Limits = Limits::default(),
) -> Bytes raise BacnetError {
  if value.device.kind != 8 ||
    value.device.instance == 4194303 ||
    value.name.is_empty() {
    raise Invalid("I-Have identity", 0)
  }
  encode_tags(
    [
      Application(Object(value.device)),
      Application(Object(value.object)),
      Application(Text(value.name)),
    ],
    limits~,
  )
}

///|
pub fn decode_i_have(
  bytes : Bytes,
  limits~ : Limits = Limits::default(),
) -> IHave raise BacnetError {
  let result : IHave = match decode_tags(bytes, limits~)[:] {
    [
      Application(Object(device)),
      Application(Object(object)),
      Application(Text(name)),
    ] => { device, object, name, }
    _ => raise Invalid("I-Have sequence", 0)
  }
  ignore(encode_i_have(result, limits~))
  result
}

///|
fn Device::discover_object(
  self : Device,
  query : WhoHas,
) -> IHave? raise BacnetError {
  if (query.range.low is Some(low) && self.id.instance < low) ||
    (query.range.high is Some(high) && self.id.instance > high) {
    return None
  }
  for object in self.objects {
    let name = match object.find(77U).values[:] {
      [Application(Text(name))] => name
      _ => raise State("invalid object name")
    }
    let matches = match query.object {
      Identifier(id) => id == object.id
      Name(wanted) => wanted == name
    }
    if matches {
      return Some({ device: self.id, object: object.id, name, })
    }
  }
  None
}

///|
pub extend ObjectQuery with @debug.Debug::{to_repr}

///|
pub extend ObjectQuery with Eq::{equal, not_equal}

///|
pub extend WhoHas with @debug.Debug::{to_repr}

///|
pub extend IHave with @debug.Debug::{to_repr}
