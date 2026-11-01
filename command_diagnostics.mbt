///|
pub(all) struct CommandSnapshot {
  object : ObjectId
  effective : Value
  relinquish_default : Value
  active_priority : Int32?
  occupied : Array[(Int32, Value)]
}

///|
/// Detached explanation of all active command intents, including overridden
/// slots. Command priority represents arbitration, not access authorization.
pub fn Device::command_snapshot(
  self : Device,
  id : ObjectId,
) -> CommandSnapshot raise BacnetError {
  let object = self.find(id)
  guard object.command is Some(command) else { raise Property(2U, 32U) }
  let occupied : Array[(Int32, Value)] = []
  for i, slot in command.slots {
    if slot is Some(value) {
      occupied.push((i + 1, value))
    }
  }
  {
    object: id,
    effective: command.effective(),
    relinquish_default: command.default_value(),
    active_priority: command.active_priority(),
    occupied,
  }
}
