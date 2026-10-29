priv struct PropertyEntry {
  id : UInt
  mut values : Array[Tag]
  writable : Bool
  array : Bool
}

priv struct DeviceObject {
  id : ObjectId
  properties : Array[PropertyEntry]
  mut command : PriorityArray?
}

pub struct Device {
  priv id : ObjectId
  priv vendor : UInt
  priv limits : Limits
  priv objects : Array[DeviceObject]
  priv mut stored_bytes : Int
}

pub fn Device::new(instance : Int, name : String, vendor : UInt, limits? : Limits = Limits::default()) -> Device raise BacnetError {
  limits.validate()
  if vendor > 65535U { raise Invalid("vendor identifier", 0) }
  let id = ObjectId::new(8, instance)
  let device : Device = { id, vendor, limits, objects: [], stored_bytes: 0 }
  device.add_object(id, name)
  device.define(id, 120U, [Application(Unsigned(vendor))])
  device.define(id, 62U, [Application(Unsigned(1476U))])
  device.define(id, 107U, [Application(Enumerated(3U))])
  device
}

pub fn Device::identifier(self : Device) -> ObjectId { self.id }

pub fn Device::resource_limits(self : Device) -> Limits { self.limits }

fn Device::find(self : Device, id : ObjectId) -> DeviceObject raise BacnetError {
  for object in self.objects { if object.id == id { return object } }
  raise Property(1U, 31U)
}

fn DeviceObject::find(self : DeviceObject, id : UInt) -> PropertyEntry raise BacnetError {
  for property in self.properties { if property.id == id { return property } }
  raise Property(2U, 32U)
}

pub fn Device::add_object(self : Device, id : ObjectId, name : String) -> Unit raise BacnetError {
  if self.objects.length() >= self.limits.max_objects { raise Limit("object count") }
  if self.limits.max_properties < 3 { raise Limit("mandatory object properties") }
  if id.kind == 8 && id != self.id { raise State("one device object per registry") }
  for object in self.objects {
    if object.id == id { raise State("duplicate object identifier") }
    if object.find(77U).values is [Application(Text(existing))] && existing == name {
      raise State("duplicate object name")
    }
  }
  if name.is_empty() { raise Invalid("empty object name", 0) }
  let properties = [
    { id: 75U, values: [Application(Object(id))], writable: false, array: false },
    { id: 77U, values: [Application(Text(name))], writable: false, array: false },
    { id: 79U, values: [Application(Enumerated(id.kind.reinterpret_as_uint()))], writable: false, array: false },
  ]
  let mut added = 0
  for p in properties { added += encode_tags(p.values, limits=self.limits).length() }
  if added > self.limits.max_bytes - self.stored_bytes { raise Limit("aggregate stored property bytes") }
  self.objects.push({ id, properties, command: None })
  self.stored_bytes += added
}

pub fn Device::define(self : Device, id : ObjectId, property : UInt, value : Array[Tag], writable? : Bool = false, array? : Bool = false) -> Unit raise BacnetError {
  let object = self.find(id)
  if object.properties.length() >= self.limits.max_properties { raise Limit("property count") }
  if property == 76U || property == 87U || property == 104U || property == 371U {
    raise State("property is managed by registry")
  }
  for entry in object.properties { if entry.id == property { raise State("duplicate property") } }
  if !array && value.length() != 1 { raise Invalid("scalar property requires one value", 0) }
  if writable && (array || !(value is [Application(_)])) { raise Unsupported("writable compound or array property") }
  let wire = encode_tags(value, limits=self.limits)
  if wire.length() > self.limits.max_bytes - self.stored_bytes { raise Limit("aggregate stored property bytes") }
  let frozen = decode_tags(wire, limits=self.limits)
  object.properties.push({ id: property, values: frozen, writable, array })
  self.stored_bytes += wire.length()
}

fn indexed(value : Array[Tag], array : Bool, index : UInt?) -> Array[Tag] raise BacnetError {
  match index {
    None => value.copy()
    Some(0U) if array => [Application(Unsigned(value.length().reinterpret_as_uint()))]
    Some(i) if array => {
      if i > value.length().reinterpret_as_uint() { raise Property(2U, 42U) }
      [value[i.reinterpret_as_int()-1]]
    }
    Some(_) => raise Property(2U, 50U)
  }
}

pub fn Device::read(self : Device, reference : PropertyRef) -> Array[Tag] raise BacnetError {
  let object = self.find(reference.object)
  let (value, array) = match reference.property {
    76U if reference.object == self.id => (self.objects.map(fn(o) { Application(Object(o.id)) }), true)
    371U => (self.property_ids(reference.object).map(fn(p) { Application(Enumerated(p)) }), true)
    87U => match object.command { Some(c) => (c.values(), true); None => raise Property(2U, 32U) }
    104U => match object.command { Some(c) => ([Application(c.default_value())], false); None => raise Property(2U, 32U) }
    85U if object.command is Some(c) => ([Application(c.effective())], false)
    _ => { let p = object.find(reference.property); (p.values, p.array) }
  }
  clone_tags(indexed(value, array, reference.index), self.limits)
}

pub fn Device::property_ids(self : Device, id : ObjectId) -> Array[UInt] raise BacnetError {
  let object = self.find(id)
  let result = object.properties.map(fn(p) { p.id })
  if id == self.id { result.push(76U) }
  if object.command is Some(_) { result.push(87U); result.push(104U) }
  // Property_List excludes the three mandatory identification properties and itself.
  result.filter(fn(p) { p != 75U && p != 77U && p != 79U })
}

pub fn Device::all_property_ids(self : Device, id : ObjectId) -> Array[UInt] raise BacnetError {
  let result = [75U, 77U, 79U, 371U]
  for p in self.property_ids(id) { result.push(p) }
  result
}
