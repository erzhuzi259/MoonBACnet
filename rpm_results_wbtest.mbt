///|
test "RPM correlation preserves device errors and rejects stale array indexes" {
  let object = ObjectId::new(2, 1)
  let first : PropertyRef = { object, property: 85U, index: None, }
  let second : PropertyRef = { object, property: 87U, index: Some(3U), }
  let request = encode_read_multiple([
    { object, properties: [(85U, None), (87U, Some(3U))], },
  ])
  let value = PropertyData(first, [Application(Real(22.0F))])
  let ack = encode_multiple_ack([
    { object, results: [value, PropertyFailure(second, 2U, 42U)], },
  ])
  assert_true(
    correlate_read_multiple(request, ack)[1] is PropertyFailure(_, 2U, 42U),
  )
  let wrong = encode_multiple_ack([
    {
      object,
      results: [value, PropertyFailure({ ..second, index: Some(4U), }, 2U, 42U)],
    },
  ])
  assert_true(
    try {
      ignore(correlate_read_multiple(request, wrong))
      false
    } catch {
      _ => true
    },
  )
}
