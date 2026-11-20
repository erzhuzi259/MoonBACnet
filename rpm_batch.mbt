///|
pub(all) struct ReadBatch {
  body : Bytes
  access : Array[ReadAccess]
}

///|
/// Compile a read plan whose segments carry their validated request keys.
pub fn compile_read_batches(
  peer : DiscoveredDevice,
  access : Array[ReadAccess],
  limits~ : Limits = Limits::default(),
) -> Array[ReadBatch] raise BacnetError {
  plan_read_multiple(peer, access, limits~).map(body => {
    body,
    access: decode_read_multiple(body, limits~),
  })
}
