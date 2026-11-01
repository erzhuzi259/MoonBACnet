///|
fn main raise {
  let directory = @bac.DiscoveryDirectory::new()
  let device = @bac.Device::new(42, "equipment-gateway", 999U)
  assert_true(directory.observe("local-device", device.announcement(), 10UL))
  let point = @bac.ObjectId::new(2, 1)
  device.add_point(point, "setpoint", Analog, Real(19.0F), commandable=true)
  let reference : @bac.PropertyRef = {
    object: point,
    property: 85U,
    index: None,
  }
  device.write({
    reference,
    value: [Application(Real(21.0F))],
    priority: Some(12),
  })
  device.write({
    reference,
    value: [Application(Real(24.0F))],
    priority: Some(8),
  })
  let status = device.command_snapshot(point)
  assert_eq(status.occupied.length(), 2)
  assert_eq(status.active_priority, Some(8))
  device.write({ reference, value: [Application(Null)], priority: Some(8), })
  assert_eq(device.command_snapshot(point).active_priority, Some(12))
  assert_eq(directory.expire(40UL, 30UL).length(), 1)
  println(
    "Gateway inventory expires stale devices; command diagnostics explain operator override and policy restoration",
  )
}
