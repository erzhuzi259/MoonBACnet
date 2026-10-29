///|
pub fn Device::add_point(
  self : Device,
  id : ObjectId,
  name : String,
  domain : CommandDomain,
  initial : Value,
  commandable~ : Bool = false,
  units~ : UInt32 = 95U,
) -> Unit raise BacnetError {
  domain_validate(domain, initial)
  let valid_kind = match domain {
    Analog => id.kind == 0 || id.kind == 1 || id.kind == 2
    Binary => id.kind == 3 || id.kind == 4 || id.kind == 5
    MultiState(_) => id.kind == 13 || id.kind == 14 || id.kind == 19
  }
  if !valid_kind {
    raise Invalid("object type and point domain mismatch", 0)
  }
  if commandable && (id.kind == 0 || id.kind == 3 || id.kind == 13) {
    raise Invalid("input point cannot be commandable", 0)
  }
  // Construct a complete candidate before changing the live registry.
  let temp : Device = {
    id: self.id,
    vendor: self.vendor,
    limits: self.limits,
    objects: [],
    stored_bytes: 0,
  }
  temp.add_object(id, name)
  temp.define_property(id, 85U, [Application(initial)], writable=commandable)
  temp.define_property(id, 111U, [Application(Bits(4, b"\x00"))])
  temp.define_property(id, 81U, [Application(Boolean(false))])
  match domain {
    Analog => {
      temp.define_property(id, 117U, [Application(Enumerated(units))])
      temp.define_property(id, 22U, [Application(Real(0.0F))])
    }
    MultiState(count) =>
      temp.define_property(id, 74U, [Application(Unsigned(count))])
    Binary => ()
  }
  if commandable {
    if temp.objects[0].properties.length() + 2 > self.limits.max_properties {
      raise Limit("command property count")
    }
    temp.objects[0].command = Some(PriorityArray::new(domain, initial))
    temp.stored_bytes += 85
  }
  if temp.stored_bytes > self.limits.max_bytes - self.stored_bytes {
    raise Limit("aggregate point bytes")
  }
  self.add_object(id, name)
  let candidate = temp.objects[0]
  let target = self.objects[self.objects.length() - 1]
  for i = 3; i < candidate.properties.length(); i = i + 1 {
    target.properties.push(candidate.properties[i])
  }
  target.command = candidate.command
  let mut identification_bytes = 0
  for i = 0; i < 3; i = i + 1 {
    identification_bytes += encode_tags(
      candidate.properties[i].values,
      limits=self.limits,
    ).length()
  }
  self.stored_bytes += temp.stored_bytes - identification_bytes
}

///|
fn Device::replace_scalar(
  self : Device,
  property : PropertyEntry,
  value : Value,
) -> Unit raise BacnetError {
  let old = match property.values[:] {
    [Application(old)] => old
    _ => raise Property(2U, 9U)
  }
  let (old_kind, _) = application_body(old, self.limits)
  let (new_kind, _) = application_body(value, self.limits)
  if old_kind != new_kind {
    raise Property(2U, 9U)
  }
  let candidate = [Application(value)]
  let old_size = encode_tags(property.values, limits=self.limits).length()
  let wire = encode_tags(candidate, limits=self.limits)
  if wire.length() > self.limits.max_bytes - (self.stored_bytes - old_size) {
    raise Limit("aggregate replacement bytes")
  }
  let snapshot = decode_tags(wire, limits=self.limits)
  property.values = snapshot
  self.stored_bytes = self.stored_bytes - old_size + wire.length()
}

///|
fn Device::point_domain(
  _self : Device,
  object : DeviceObject,
) -> CommandDomain raise BacnetError {
  match object.id.kind {
    0 | 1 | 2 => Analog
    3 | 4 | 5 => Binary
    13 | 14 | 19 =>
      match object.find(74U).values[:] {
        [Application(Unsigned(count))] => MultiState(count)
        _ => raise State("invalid configured state count")
      }
    _ => raise Unsupported("object type does not have point semantics")
  }
}

///|
pub fn Device::update(
  self : Device,
  id : ObjectId,
  property : UInt32,
  value : Value,
) -> Unit raise BacnetError {
  let object = self.find(id)
  if property == 75U || property == 77U || property == 79U || property == 74U {
    raise State("immutable object identity or domain")
  }
  if property == 85U {
    if object.command is Some(_) {
      raise State("commandable value must be written through a priority")
    }
    domain_validate(self.point_domain(object), value)
  }
  if property == 22U {
    match value {
      Real(v) if v >= 0.0F &&
        (v.reinterpret_as_uint() & 0x7f800000U) != 0x7f800000U => ()
      _ => raise Property(2U, 37U)
    }
  }
  self.replace_scalar(object.find(property), value)
}

///|
pub fn Device::write(
  self : Device,
  request : WriteProperty,
) -> Unit raise BacnetError {
  let object = self.find(request.reference.object)
  if request.reference.index is Some(_) {
    ignore(self.read(request.reference))
    raise Property(2U, 40U)
  }
  let value = match request.value[:] {
    [Application(value)] => value
    _ => raise Property(2U, 9U)
  }
  if request.reference.property == 85U && object.command is Some(command) {
    let priority = request.priority.unwrap_or(16)
    command.write(priority, value)
    return
  }
  if request.priority is Some(_) {
    raise Property(2U, 40U)
  }
  let property = object.find(request.reference.property)
  if !property.writable {
    raise Property(2U, 40U)
  }
  self.replace_scalar(property, value)
}

///|
pub fn Device::set_relinquish_default(
  self : Device,
  id : ObjectId,
  value : Value,
) -> Unit raise BacnetError {
  match self.find(id).command {
    Some(command) => command.set_default(value)
    None => raise Property(2U, 32U)
  }
}

///|
pub fn Device::active_priority(
  self : Device,
  id : ObjectId,
) -> Int32? raise BacnetError {
  match self.find(id).command {
    Some(command) => command.active_priority()
    None => raise Property(2U, 32U)
  }
}

///|
pub fn Device::announcement(self : Device) -> IAm {
  { device: self.id, vendor: self.vendor, segmentation: 3U, max_apdu: 1476U, }
}
