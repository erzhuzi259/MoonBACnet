///|
test "batch correlation rejects an incomplete response vector" {
  let batch : ReadBatch = { body: b"", access: [], }
  let failed = try {
    ignore(correlate_read_batches([batch], []))
    false
  } catch {
    Invalid(_, _) => true
    _ => false
  }
  assert_true(failed)
  assert_true(correlate_read_batches([], []).is_empty())
}

///|
test "batch correlation applies each reply to its own object and preserves errors" {
  let a = ObjectId::new(2, 1)
  let b = ObjectId::new(2, 2)
  let ref_a : PropertyRef = { object: a, property: 85U, index: None, }
  let ref_b : PropertyRef = { object: b, property: 85U, index: None, }
  let plan = [a, b].map(object => {
    let access = [{ object, properties: [(85U, None)], }]
    { body: encode_read_multiple(access), access, }
  })
  let reply_a = encode_multiple_ack([
    { object: a, results: [PropertyData(ref_a, [Application(Real(21.0F))])], },
  ])
  let reply_b = encode_multiple_ack([
    { object: b, results: [PropertyFailure(ref_b, 2U, 42U)], },
  ])
  let result = correlate_read_batches(plan, [reply_a, reply_b])
  assert_true(result[0] is PropertyData(_, _))
  assert_true(result[1] is PropertyFailure(_, 2U, 42U))
  let swapped = try {
    ignore(correlate_read_batches(plan, [reply_b, reply_a]))
    false
  } catch {
    _ => true
  }
  assert_true(swapped)
}
