///|
test "read batches carry exactly the keys represented on the wire" {
  let object = ObjectId::new(8, 7)
  let peer : DiscoveredDevice = {
    peer: "device",
    announcement: {
      device: object,
      max_apdu: 50U,
      segmentation: 3U,
      vendor: 1U,
    },
    first_seen: 0UL,
    last_seen: 0UL,
  }
  let access = [
    {
      object,
      properties: Array::makei(42, i => (i.reinterpret_as_uint() + 200U, None)),
    },
  ]
  let plan = compile_read_batches(peer, access)
  assert_true(plan.length() > 1)
  let merged = []
  for segment in plan {
    assert_true(segment.body.length() <= 46)
    let decoded = decode_read_multiple(segment.body)
    assert_eq(decoded[0].properties, segment.access[0].properties)
    for item in segment.access {
      merged.append(item.properties)
    }
  }
  assert_eq(merged, access[0].properties)
}
