fn scalar_wire(device : Device, id : ObjectId, property? : UInt = 85U) -> Bytes raise BacnetError {
  encode_tags(device.read(reference(id, property~)))
}

test "priority slots resolve minimum occupied priority and relinquish to default" {
  let p = PriorityArray::new(Analog, Real(19.0F))
  assert_eq(p.active_priority(), None)
  p.write(16, Real(20.0F))
  p.write(8, Real(21.0F))
  p.write(1, Real(25.0F))
  assert_eq(p.active_priority(), Some(1))
  p.write(1, Null)
  assert_eq(p.active_priority(), Some(8))
  p.write(8, Null)
  p.write(16, Null)
  p.set_default(Real(18.0F))
  assert_eq(encode_tags([Application(p.effective())]), encode_tags([Application(Real(18.0F))]))
  assert_eq(p.values().length(), 16)
  expect_error(() => { p.write(6, Real(30.0F)) })
  expect_error(() => { p.write(0, Null) })
  expect_error(() => { p.write(17, Null) })
}

test "priority domains reject invalid numeric states and preserve old command on failure" {
  let binary = PriorityArray::new(Binary, Enumerated(0U))
  binary.write(4, Enumerated(1U))
  expect_error(() => { binary.write(4, Enumerated(2U)) })
  expect_error(() => { binary.write(4, Unsigned(1U)) })
  assert_eq(encode_tags([Application(binary.effective())]), b"\x91\x01")
  let multi = PriorityArray::new(MultiState(3U), Unsigned(1U))
  expect_error(() => { multi.write(8, Unsigned(0U)) })
  expect_error(() => { multi.write(8, Unsigned(4U)) })
  expect_error(() => { ignore(PriorityArray::new(MultiState(0U), Unsigned(1U))) })
  let analog = PriorityArray::new(Analog, Real(0.0F))
  expect_error(() => { analog.write(8, Real(Float::reinterpret_from_uint(0x7f800000U))) })
  expect_error(() => { analog.write(8, Real(Float::reinterpret_from_uint(0x7fc00000U))) })
}

test "registry object list array indexing and property list exclude mandatory identifiers" {
  let d = Device::new(42,"lab",999U)
  let id = ObjectId::new(0,1)
  d.add_point(id,"temperature",Analog,Real(20.0F),units=62U)
  assert_eq(encode_tags(d.read(reference(d.identifier(),property=76U,index=Some(0U)))), b"\x21\x02")
  assert_eq(d.read(reference(d.identifier(),property=76U)).length(),2)
  assert_eq(encode_tags(d.read(reference(d.identifier(),property=76U,index=Some(2U)))),encode_tags([Application(Object(id))]))
  expect_error(() => { ignore(d.read(reference(d.identifier(),property=76U,index=Some(3U)))) })
  expect_error(() => { ignore(d.read(reference(id,index=Some(0U)))) })
  let properties = d.property_ids(id)
  assert_true(!properties.contains(75U) && !properties.contains(77U) && !properties.contains(79U) && !properties.contains(371U))
  assert_true(properties.contains(85U))
  assert_true(d.all_property_ids(id).contains(371U))
}

test "registry admission enforces identity name type counts and aggregate budget atomically" {
  let d = Device::new(42,"lab",1U,limits={ ..Limits::default(), max_objects: 2 })
  let id = ObjectId::new(0,1)
  expect_error(() => { d.add_point(id,"lab",Analog,Real(0.0F)) })
  expect_error(() => { d.add_point(id,"a",Binary,Enumerated(0U)) })
  expect_error(() => { d.add_point(id,"a",Analog,Real(0.0F),commandable=true) })
  assert_eq(d.read(reference(d.identifier(),property=76U)).length(),1)
  d.add_point(id,"temperature",Analog,Real(20.0F))
  expect_error(() => { d.add_object(ObjectId::new(0,2),"second") })
  expect_error(() => { d.add_object(id,"third") })
  expect_error(() => { ignore(Device::new(1,"x",65536U)) })
}

test "custom property snapshots isolate caller mutation and return defensive copies" {
  let d = Device::new(1,"dev",1U)
  let id = d.identifier()
  let nested : Array[Tag] = [Application(Unsigned(3U))]
  d.define_property(id,512U,[Constructed(0,nested)])
  nested.push(Application(Unsigned(4U)))
  let wire = scalar_wire(d,id,property=512U)
  let snapshot = d.read(reference(id,property=512U))
  if snapshot[0] is Constructed(_, children) { children.clear() }
  assert_eq(scalar_wire(d,id,property=512U),wire)
  d.define_property(id,513U,[],array=true)
  assert_eq(d.read(reference(id,property=513U)).length(),0)
  assert_eq(encode_tags(d.read(reference(id,property=513U,index=Some(0U)))),b"\x21\x00")
}

test "network writes enforce schema permissions and priority array behavior" {
  let d = Device::new(42,"lab",1U)
  let id = ObjectId::new(2,1)
  d.add_point(id,"setpoint",Analog,Real(19.0F),commandable=true)
  d.write({ reference: reference(id),value: [Application(Real(22.0F))],priority: None })
  assert_eq(d.active_priority(id),Some(16))
  d.write({ reference: reference(id),value: [Application(Real(24.0F))],priority: Some(8) })
  assert_eq(scalar_wire(d,id),encode_tags([Application(Real(24.0F))]))
  d.write({ reference: reference(id),value: [Application(Null)],priority: Some(8) })
  assert_eq(d.active_priority(id),Some(16))
  assert_eq(d.read(reference(id,property=87U)).length(),16)
  expect_error(() => { d.write({ reference: reference(id,property=77U),value: [Application(Text("rename"))],priority: None }) })
  expect_error(() => { d.update(id,85U,Real(2.0F)) })
  d.set_relinquish_default(id,Real(17.0F))
  d.write({ reference: reference(id),value: [Application(Null)],priority: None })
  assert_eq(scalar_wire(d,id),encode_tags([Application(Real(17.0F))]))
}

test "host sensor updates validate type domain and custom property aggregate replacement" {
  let d = Device::new(1,"d",1U,limits={ ..Limits::default(),max_bytes: 256 })
  let id = ObjectId::new(13,1)
  d.add_point(id,"mode",MultiState(3U),Unsigned(1U))
  d.update(id,85U,Unsigned(3U))
  expect_error(() => { d.update(id,85U,Unsigned(4U)) })
  expect_error(() => { d.update(id,74U,Unsigned(9U)) })
  d.define_property(d.identifier(),512U,[Application(Text("initial"))],writable=true)
  let original = scalar_wire(d,d.identifier(),property=512U)
  expect_error(() => { d.write({ reference: reference(d.identifier(),property=512U),value: [Application(Text(String::from_array(Array::make(250,'x'))))],priority: None }) })
  assert_eq(scalar_wire(d,d.identifier(),property=512U),original)
}
