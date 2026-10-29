///|
test "empty array is a present constructed property value distinct from missing field" {
  let d = Device::new(42, "d", 1U)
  d.define_property(d.identifier(), 512U, [], array=true)
  let server = Server::new(d)
  match
    request_reply(
      server,
      1,
      12,
      encode_read_property(reference(d.identifier(), property=512U)),
    ) {
    ComplexAck(_, 12, body) =>
      assert_eq(decode_property_ack(body).value.length(), 0)
    _ => fail("empty array must read successfully")
  }
  let result = encode_multiple_ack([
    {
      object: d.identifier(),
      results: [PropertyData(reference(d.identifier(), property=512U), [])],
    },
  ])
  assert_true(decode_multiple_ack(result)[0].results[0] is PropertyData(_, []))
  expect_error(() => {
    ignore(
      decode_property_ack(
        encode_read_property(reference(d.identifier(), property=512U)),
      ),
    )
  })
}

///|
test "point status flag width and out-of-service bit remain coherent" {
  let d = sample_device()
  let id = ObjectId::new(0, 1)
  d.update(id, 81U, Boolean(true))
  assert_eq(
    scalar_wire(d, id, property=111U),
    encode_tags([Application(Bits(4, b"\x10"))]),
  )
  expect_error(() => d.update(id, 111U, Bits(4, b"\x00")))
  expect_error(() => d.update(id, 111U, Bits(0, b"\x10")))
  expect_error(() => d.update(id, 111U, Bits(4, b"\x10\x00")))
  d.update(id, 111U, Bits(4, b"\x90"))
  d.update(id, 81U, Boolean(false))
  assert_eq(
    scalar_wire(d, id, property=111U),
    encode_tags([Application(Bits(4, b"\x80"))]),
  )
  expect_error(() => {
    d.add_point(ObjectId::new(1, 2), "output", Analog, Real(1.0F))
  })
}

///|
test "small configured reply budget yields bounded abort and write remains retry-safe" {
  let d = Device::new(1, "d", 1U, limits={
    ..Limits::default(),
    max_bytes: 128,
  })
  d.define_property(d.identifier(), 512U, [
    Application(
      Text(
        "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz",
      ),
    ),
  ])
  let server = Server::new(d)
  let request = encode_read_property(reference(d.identifier(), property=512U))
  assert_true(
    request_reply(server, 1, 12, request, max_apdu=0) is Abort(1, true, 11),
  )
  assert_true(request_reply(server, 2, 12, request) is ComplexAck(_, 12, _))
}

///|
test "COV admission rejects incomplete configured points and confirmed notification requests before subscribing" {
  let d = sample_device()
  let server = Server::new(d)
  let request = encode_subscribe_cov({
    process: 1U,
    object: ObjectId::new(0, 1),
    confirmed: Some(true),
    lifetime: Some(5U),
  })
  match request_reply(server, 1, 5, request) {
    ErrorPdu(_, 5, bytes) => assert_eq(decode_error(bytes), (5U, 45U))
    _ => fail("expected unsupported optional functionality service error")
  }
  assert_eq(server.notifications(0UL).length(), 0)
  let partial = ObjectId::new(0, 99)
  d.add_object(partial, "incomplete")
  d.define_property(partial, 85U, [Application(Real(0.0F))])
  let manager = CovManager::new(d)
  expect_error(() => {
    manager.subscribe(
      "a",
      {
        process: 1U,
        object: partial,
        confirmed: Some(false),
        lifetime: Some(0U),
      },
      0UL,
    )
  })
  assert_eq(manager.count(0UL), 0)
}

///|
test "computed properties count against per-object admission and wildcard device is not announced" {
  let d = Device::new(1, "d", 1U, limits={
    ..Limits::default(),
    max_properties: 8,
  })
  assert_eq(d.all_property_ids(d.identifier()).length(), 8)
  expect_error(() => d.define_property(d.identifier(), 512U, [], array=true))
  expect_error(() => d.add_point(ObjectId::new(0, 1), "t", Analog, Real(0.0F)))
  assert_eq(d.read(reference(d.identifier(), property=76U)).length(), 1)
  expect_error(() => ignore(Device::new(4194303, "wildcard", 1U)))
  expect_error(() => {
    ignore(
      encode_i_am({
        device: ObjectId::new(8, 4194303),
        max_apdu: 1476U,
        segmentation: 3U,
        vendor: 1U,
      }),
    )
  })
}
