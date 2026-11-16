///|
test "RPM planner splits requests to satisfy the local tag budget" {
  let device = Device::new(12, "test", 999U)
  let peer : DiscoveredDevice = {
    peer: "test",
    announcement: device.announcement(),
    first_seen: 0UL,
    last_seen: 0UL,
  }
  let object = ObjectId::new(2, 1)
  let properties = [(85U, Some(0U)), (77U, Some(1U)), (111U, Some(2U))]
  let limits = { ..Limits::default(), max_nodes: 4, }
  let batches = plan_read_multiple(peer, [{ object, properties, }], limits~)
  assert_eq(batches.length(), 3)
  for i, batch in batches {
    let access = decode_read_multiple(batch, limits~)
    assert_eq(access.length(), 1)
    assert_eq(access[0].object, object)
    assert_eq(access[0].properties, [properties[i]])
  }
}
