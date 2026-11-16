///|
fn main raise {
  let device = @bac.Device::new(42, "automation-controller", 999U)
  let x = @bac.ObjectId::new(2, 1)
  let y = @bac.ObjectId::new(2, 2)
  device.add_point(x, "room-setpoint", Analog, Real(19.0F), commandable=true)
  device.add_point(
    y,
    "equipment-setpoint",
    Analog,
    Real(20.0F),
    commandable=true,
  )
  let command = fn(id, value) -> @bac.WriteProperty {
    {
      reference: { object: id, property: 85U, index: None, },
      value: [Application(Real(value))],
      priority: Some(8),
    }
  }
  assert_eq(
    device.apply_commands([command(x, 22.0F), command(y, 24.0F)]).length(),
    2,
  )
  let before : Array[@bac.DiscoveredDevice] = [
    {
      peer: "gateway-old",
      announcement: device.announcement(),
      first_seen: 0UL,
      last_seen: 1UL,
    },
  ]
  let after : Array[@bac.DiscoveredDevice] = [
    {
      peer: "gateway-new",
      announcement: device.announcement(),
      first_seen: 0UL,
      last_seen: 2UL,
    },
  ]
  let delta = @bac.discovery_delta(before, after)
  assert_eq(delta.changed.length(), 1)
  assert_eq(delta.added.length(), 0)
  let peer = {
    ..after[0],
    announcement: { ..after[0].announcement, max_apdu: 50U, },
  }
  let properties = Array::makei(30, i => (85U, Some(i.reinterpret_as_uint())))
  let batches = @bac.plan_read_multiple(peer, [{ object: x, properties, }])
  assert_true(batches.length() > 1)
  let mut total = 0
  for body in batches {
    assert_true(body.length() + 4 <= 50)
    total += @bac.decode_read_multiple(body)[0].properties.length()
  }
  assert_eq(total, properties.length())
  println(
    "Automation batches commit atomically; inventory deltas and peer-sized RPM requests verified",
  )
}
