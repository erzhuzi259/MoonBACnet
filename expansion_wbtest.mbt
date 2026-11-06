///|
test "command batch rollback on late failure and detached diagnostics" {
  let d = Device::new(42, "controller", 999U)
  let x = ObjectId::new(2, 1)
  let y = ObjectId::new(2, 2)
  d.add_point(x, "x", Analog, Real(19.0F), commandable=true)
  d.add_point(y, "y", Analog, Real(20.0F), commandable=true)
  let command = fn(id, priority, value) -> WriteProperty {
    {
      reference: { object: id, property: 85U, index: None, },
      value: [Application(value)],
      priority: Some(priority),
    }
  }
  assert_true(
    try {
      ignore(
        d.apply_commands([
          command(x, 8, Real(24.0F)),
          command(y, 6, Real(25.0F)),
        ]),
      )
      false
    } catch {
      _ => true
    },
  )
  assert_eq(d.active_priority(x), None)
  let result = d.apply_commands([
    command(x, 12, Real(21.0F)),
    command(x, 8, Real(24.0F)),
    command(y, 8, Real(25.0F)),
  ])
  assert_eq(result.length(), 2)
  assert_eq(result[0].active_priority, Some(8))
  ignore(d.apply_commands([command(x, 8, Null)]))
  assert_eq(
    encode_tags([Application(d.command_snapshot(x).effective)]),
    encode_tags([Application(Real(21.0F))]),
  )
  assert_eq(result[0].active_priority, Some(8))
  assert_eq(d.apply_commands([]).length(), 0)
  assert_true(
    try {
      ignore(d.apply_commands([command(ObjectId::new(2, 9), 8, Real(1.0F))]))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "discovery differences separate topology from timestamp refreshes" {
  let a = Device::new(1, "a", 999U)
  let b = Device::new(2, "b", 999U)
  let entry = fn(peer, announcement, now) -> DiscoveredDevice {
    { peer, announcement, first_seen: 0UL, last_seen: now, }
  }
  let old = [
    entry("p1", a.announcement(), 1UL),
    entry("p2", b.announcement(), 1UL),
  ]
  let refresh = [
    entry("p1", a.announcement(), 2UL),
    entry("p2", b.announcement(), 2UL),
  ]
  assert_eq(discovery_delta(old, refresh).changed.length(), 0)
  let change = discovery_delta(old, [entry("new", a.announcement(), 3UL)])
  assert_eq(change.changed.length(), 1)
  assert_eq(change.removed.length(), 1)
  assert_eq(discovery_delta([], old).added.length(), 2)
  assert_true(
    try {
      ignore(discovery_delta(old, [old[0], old[0]]))
      false
    } catch {
      _ => true
    },
  )
  change.removed.clear()
  assert_eq(old.length(), 2)
}
