///|
test "discovery conflicts are explicit and stale identities expire without wrap" {
  let directory = @moonbacnet.DiscoveryDirectory::new(maximum=1)
  let device = @moonbacnet.Device::new(42, "demo", 999U)
  assert_true(directory.observe("gateway-A", device.announcement(), 10UL))
  assert_true(!directory.observe("gateway-A", device.announcement(), 15UL))
  assert_true(
    try {
      ignore(directory.observe("gateway-B", device.announcement(), 16UL))
      false
    } catch {
      _ => true
    },
  )
  directory.devices().clear()
  assert_eq(directory.devices().length(), 1)
  assert_eq(directory.expire(19UL, 5UL).length(), 0)
  assert_eq(directory.expire(20UL, 5UL).length(), 1)
  assert_true(
    try {
      ignore(directory.expire(19UL, 5UL))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    directory.observe(
      "gateway-B",
      device.announcement(),
      18446744073709551615UL,
    ),
  )
  assert_eq(directory.expire(18446744073709551615UL, 1UL).length(), 0)
}

///|
test "command snapshots explain overridden intents and remain detached after release" {
  let d = @moonbacnet.Device::new(2, "plant", 999U)
  let id = @moonbacnet.ObjectId::new(2, 1)
  d.add_point(id, "setpoint", Analog, Real(18.0F), commandable=true)
  let reference : @moonbacnet.PropertyRef = {
    object: id,
    property: 85U,
    index: None,
  }
  d.write({ reference, value: [Application(Real(20.0F))], priority: Some(12), })
  d.write({ reference, value: [Application(Real(24.0F))], priority: Some(8), })
  let snapshot = d.command_snapshot(id)
  assert_eq(snapshot.active_priority, Some(8))
  assert_eq(snapshot.occupied.length(), 2)
  snapshot.occupied.clear()
  d.write({ reference, value: [Application(Null)], priority: Some(8), })
  let restored = d.command_snapshot(id)
  assert_eq(restored.active_priority, Some(12))
  assert_true(restored.effective is Real(20.0F))
  assert_true(snapshot.effective is Real(24.0F))
}
