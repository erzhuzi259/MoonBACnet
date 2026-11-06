///|
/// Atomic local command plan; not network WritePropertyMultiple/persistence.
pub fn Device::apply_commands(
  self : Device,
  requests : Array[WriteProperty],
) -> Array[CommandSnapshot] raise BacnetError {
  if requests.length() > self.limits.max_pending {
    raise Limit("command batch")
  }
  let objects : Array[DeviceObject] = []
  let commands : Array[PriorityArray] = []
  for request in requests {
    if request.reference.property != 85U || request.reference.index is Some(_) {
      raise Property(2U, 40U)
    }
    let object = self.find(request.reference.object)
    let mut index = -1
    for i, staged in objects {
      if staged.id == object.id {
        index = i
        break
      }
    }
    if index < 0 {
      let current = match object.command {
        Some(c) => c
        None => raise Property(2U, 40U)
      }
      index = objects.length()
      objects.push(object)
      commands.push({
        domain: current.domain,
        fallback: current.fallback,
        slots: current.slots.copy(),
      })
    }
    let value = match request.value[:] {
      [Application(v)] => v
      _ => raise Property(2U, 9U)
    }
    commands[index].write(request.priority.unwrap_or(16), value)
  }
  for i, object in objects {
    object.command = Some(commands[i])
  }
  objects.map(object => self.command_snapshot(object.id))
}
