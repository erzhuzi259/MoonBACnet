///|
test "RPM batches respect peer APDU size and preserve indexed property order" {
  let peer : DiscoveredDevice = {
    peer: "building-a",
    announcement: {
      device: { kind: 8, instance: 45, },
      max_apdu: 50U,
      segmentation: 3U,
      vendor: 1U,
    },
    first_seen: 0UL,
    last_seen: 0UL,
  }
  let object : ObjectId = { kind: 2, instance: 8, }
  let properties = Array::makei(40, i => (85U, Some(i.reinterpret_as_uint())))
  let input : Array[ReadAccess] = [{ object, properties, }]
  let planned = plan_read_multiple(peer, input)
  assert_true(planned.length() > 1)
  let actual = []
  for body in planned {
    let apdu = encode_apdu(Confirmed(Request::new(0, 14, body)))
    assert_true(apdu.length() <= 50)
    for entry in decode_read_multiple(body) {
      assert_true(entry.object == object)
      for property in entry.properties {
        actual.push(property)
      }
    }
  }
  assert_true(actual == properties)
  assert_true(
    try {
      ignore(
        plan_read_multiple(peer, input, limits={
          ..Limits::default(),
          max_pending: 1,
        }),
      )
      false
    } catch {
      _ => true
    },
  )
}
