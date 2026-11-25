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
  let directory = @bac.DiscoveryDirectory::new()
  let announcement = { ..device.announcement(), max_apdu: 50U, }
  assert_true(directory.observe("gateway-new", announcement, 2UL))
  let peer = directory
    .lookup(announcement.device, 3UL, max_age=Some(10UL))
    .unwrap()
  let missing = @bac.ObjectId::new(2, 3)
  let properties = Array::makei(17, i => (87U, Some(i.reinterpret_as_uint())))
  let plan = @bac.compile_read_batches(peer, [
    { object: x, properties, },
    { object: y, properties: [(85U, None)], },
    { object: missing, properties: [(85U, None)], },
  ])
  assert_true(plan.length() > 1)
  let client = @bac.Client::new()
  let server = @bac.Server::new(device)
  let replies : Array[Bytes] = []
  let mut now = 3UL
  for batch in plan {
    assert_true(batch.body.length() + 4 <= 50)
    let tx = client.start(peer.peer, 14, batch.body, now)
    assert_eq(client.next_deadline(), Some(now + 3UL))
    now += 1UL
    let reply = server.datagram(tx.bytes, "collector", now).unwrap()
    match client.receive(peer.peer, @bac.decode_datagram(reply), now) {
      Some(Completed(ComplexAck(_, 14, body))) => replies.push(body)
      _ => raise Failure("expected a ReadPropertyMultiple acknowledgement")
    }
  }
  assert_eq(client.next_deadline(), None)
  let outcomes = @bac.correlate_read_batches(plan, replies)
  assert_eq(outcomes.length(), 19)
  assert_true(outcomes[0] is PropertyData(_, [Application(Unsigned(16U))]))
  assert_true(outcomes[1] is PropertyData({ index: Some(1U), .. }, _))
  assert_true(outcomes[17] is PropertyData(_, [Application(Real(24.0F))]))
  assert_true(
    outcomes[18] is PropertyFailure(reference, _, _) &&
    reference.object == missing,
  )
  println(
    "Atomic commands, device migration and APDU-bounded reads with independent property outcomes verified",
  )
}
