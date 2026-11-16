///|
/// Match one ReadPropertyMultiple acknowledgement to its exact request body.
/// Returns ordered property outcomes, including device-reported failures.
/// Special selectors with expanded replies are outside this exact-key check.
pub fn correlate_read_multiple(
  request : Bytes,
  acknowledgement : Bytes,
  limits~ : Limits = Limits::default(),
) -> Array[ReadResult] raise BacnetError {
  let expected = decode_read_multiple(request, limits~)
  let actual = decode_multiple_ack(acknowledgement, limits~)
  if expected.length() != actual.length() {
    raise Invalid("RPM acknowledgement access count differs", 0)
  }
  let ordered : Array[ReadResult] = []
  for i, access in expected {
    let result = actual[i]
    if result.object != access.object ||
      result.results.length() != access.properties.length() {
      raise Invalid("RPM acknowledgement object or result count differs", i)
    }
    for j, property in access.properties {
      let outcome = result.results[j]
      let reference = match outcome {
        PropertyData(reference, _) | PropertyFailure(reference, _, _) =>
          reference
      }
      if (reference.property, reference.index) != property {
        raise Invalid("RPM acknowledgement property or array index differs", j)
      }
      ordered.push(outcome)
    }
  }
  ordered
}
