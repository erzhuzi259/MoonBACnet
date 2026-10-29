fn reference(id : ObjectId, property? : UInt = 85U, index? : UInt? = None) -> PropertyRef {
  { object: id, property, index }
}

test "WhoIs ranges IAm segmentation and vendor fields validate independently" {
  for query in [{ low: None, high: None }, { low: Some(100), high: Some(200) }, { low: Some(4194303), high: Some(4194303) }] {
    let bytes = encode_who_is(query)
    assert_eq(encode_who_is(decode_who_is(bytes)), bytes)
  }
  let iam : IAm = { device: ObjectId::new(8, 1234), max_apdu: 1476U, segmentation: 3U, vendor: 65535U }
  let wire = encode_i_am(iam)
  let decoded = decode_i_am(wire)
  assert_eq(decoded.device, iam.device)
  assert_eq(decoded.vendor, 65535U)
  expect_error(() => { ignore(encode_who_is({ low: Some(0), high: None })) })
  expect_error(() => { ignore(encode_who_is({ low: Some(20), high: Some(10) })) })
  expect_error(() => { ignore(decode_who_is(b"\x09\x01")) })
  expect_error(() => { ignore(encode_i_am({ ..iam, segmentation: 4U })) })
  expect_error(() => { ignore(encode_i_am({ ..iam, device: ObjectId::new(0, 1) })) })
}

test "property services distinguish absent index zero and element selections" {
  let id = ObjectId::new(8, 42)
  for index in [None, Some(0U), Some(1U), Some(4294967295U)] {
    let r = reference(id, property=76U, index~)
    let bytes = encode_read_property(r)
    assert_eq(decode_read_property(bytes), r)
    let ack : PropertyValue = { reference: r, value: [Application(Unsigned(3U))] }
    assert_eq(encode_property_ack(decode_property_ack(encode_property_ack(ack))), encode_property_ack(ack))
  }
  expect_error(() => { ignore(decode_read_property(b"\x19\x55\x0c\x02\x00\x00\x2a")) })
  expect_error(() => { ignore(decode_read_property(encode_tags([context_object(0,id), context_uint(1,85U), context_uint(1,1U)]))) })
  expect_error(() => { ignore(encode_property_ack({ reference: reference(id), value: [] })) })
}

test "write priority Null relinquish and constructed body survive service codecs" {
  let id = ObjectId::new(2, 1)
  for priority in [None, Some(1), Some(6), Some(16)] {
    let write : WriteProperty = { reference: reference(id), value: [Application(Null)], priority }
    let bytes = encode_write_property(write)
    assert_eq(encode_write_property(decode_write_property(bytes)), bytes)
  }
  expect_error(() => { ignore(encode_write_property({ reference: reference(id), value: [Application(Real(1.0F))], priority: Some(0) })) })
  expect_error(() => { ignore(decode_write_property(encode_read_property(reference(id)))) })
  assert_eq(decode_error(encode_error(2U,40U)), (2U,40U))
  expect_error(() => { ignore(decode_error(b"\x21\x02\x91\x28")) })
}

test "multiple access success and error results preserve requested object and index" {
  let id = ObjectId::new(2, 1)
  let access : Array[ReadAccess] = [{ object: id, properties: [(85U,None), (87U,Some(0U))] },
    { object: ObjectId::new(8,42), properties: [(8U,None)] }]
  let bytes = encode_read_multiple(access)
  assert_eq(encode_read_multiple(decode_read_multiple(bytes)), bytes)
  let result : Array[ReadAccessResult] = [{ object: id, results: [
    PropertyData(reference(id), [Application(Real(20.0F))]),
    PropertyFailure(reference(id, property=9999U, index=Some(3U)), 2U,32U)] }]
  let ack = encode_multiple_ack(result)
  assert_eq(encode_multiple_ack(decode_multiple_ack(ack)), ack)
  expect_error(() => { ignore(encode_read_multiple([])) })
  expect_error(() => { ignore(encode_read_multiple([{ object: id, properties: [] }])) })
  expect_error(() => { ignore(encode_multiple_ack([{ object: ObjectId::new(0,2), results: result[0].results }])) })
}

test "COV cancellation is missing fields while false and zero create perpetual subscription" {
  let id = ObjectId::new(0,1)
  let cancel : SubscribeCov = { process: 4294967295U, object: id, confirmed: None, lifetime: None }
  let permanent : SubscribeCov = { ..cancel, confirmed: Some(false), lifetime: Some(0U) }
  assert_true(encode_subscribe_cov(cancel) != encode_subscribe_cov(permanent))
  for sub in [cancel, permanent, { ..permanent, confirmed: Some(true), lifetime: Some(300U) }] {
    let bytes = encode_subscribe_cov(sub)
    assert_eq(encode_subscribe_cov(decode_subscribe_cov(bytes)), bytes)
  }
  expect_error(() => { ignore(encode_subscribe_cov({ ..cancel, confirmed: Some(false) })) })
  expect_error(() => { ignore(encode_subscribe_cov({ ..cancel, lifetime: Some(0U) })) })
  expect_error(() => { ignore(decode_subscribe_cov(encode_tags([context_uint(0,1U),context_object(1,id), Context(2,b"\x02"),context_uint(3,0U)]))) })
}

test "COV notifications preserve multiple properties and reject incomplete values" {
  let n : CovNotification = { process: 7U, device: ObjectId::new(8,42), object: ObjectId::new(0,1), remaining: 15U,
    values: [{ property: 85U, index: None, value: [Application(Real(23.0F))], priority: Some(8) },
      { property: 111U, index: None, value: [Application(Bits(4,b"\x80"))], priority: None }] }
  let bytes = encode_cov(n)
  assert_eq(encode_cov(decode_cov(bytes)), bytes)
  expect_error(() => { ignore(encode_cov({ ..n, values: [] })) })
  expect_error(() => { ignore(encode_cov({ ..n, values: [{ ..n.values[0], value: [] }] })) })
}
