///|
/// Validate all responses against a read plan before returning any outcomes.
pub fn correlate_read_batches(
  plan : Array[ReadBatch],
  acknowledgements : Array[Bytes],
  limits~ : Limits = Limits::default(),
) -> Array[ReadResult] raise BacnetError {
  limits.validate()
  if plan.length() != acknowledgements.length() {
    raise Invalid("RPM batch reply count differs", 0)
  }
  if plan.length() > limits.max_pending {
    raise Limit("RPM reply segment count")
  }
  let results : Array[ReadResult] = []
  let mut bytes = 0
  for i, segment in plan {
    let response = acknowledgements[i]
    if segment.body.length() > limits.max_bytes - bytes {
      raise Limit("RPM correlation bytes")
    }
    bytes += segment.body.length()
    if response.length() > limits.max_bytes - bytes {
      raise Limit("RPM correlation bytes")
    }
    bytes += response.length()
    results.append(correlate_read_multiple(segment.body, response, limits~))
  }
  results
}
