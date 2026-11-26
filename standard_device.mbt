///|
#derive(Debug)
pub(all) struct Ipv4PortConfig {
  instance : Int32
  name : String
  address : Bytes
  subnet_mask : Bytes
  gateway : Bytes
  udp_port : UInt32
}

///|
/// Construct a device with revision-22 identity and an explicit ordinary IPv4 port.
/// The host must bind this configuration to the actual transport.
pub fn Device::new_standard(
  instance : Int32,
  name : String,
  vendor : UInt32,
  port : Ipv4PortConfig,
  limits~ : Limits = Limits::default(),
) -> Device raise BacnetError {
  if port.address.length() != 4 ||
    port.subnet_mask.length() != 4 ||
    port.gateway.length() != 4 ||
    port.udp_port == 0U ||
    port.udp_port > 65535U {
    raise Invalid("IPv4 port configuration", 0)
  }
  let device = Device::new(instance, name, vendor, limits~)
  let id = device.id
  for
    (property, value) in [
      (112U, Enumerated(0U)),
      (121U, Text("MoonBACnet")),
      (70U, Text("MoonBit device")),
      (44U, Text("software")),
      (12U, Text("0.2.0+standard")),
      (98U, Unsigned(1U)),
      (139U, Unsigned(22U)),
      (11U, Unsigned(3000U)),
      (73U, Unsigned(2U)),
      (155U, Unsigned(0U)),
    ] {
    device.define_property(id, property, [Application(value)])
  }
  device.define_property(id, 30U, [], array=true)
  let network = ObjectId::new(56, port.instance)
  device.add_object(network, port.name)
  for
    (property, value) in [
      (111U, Bits(4, b"\x00")),
      (103U, Enumerated(0U)),
      (81U, Boolean(false)),
      (427U, Enumerated(5U)),
      (482U, Enumerated(2U)),
      (416U, Boolean(false)),
      (420U, Real(0.0F)),
      (425U, Unsigned(0U)),
      (426U, Enumerated(0U)),
      (399U, Unsigned(1476U)),
      (408U, Enumerated(0U)),
      (400U, Octets(port.address)),
      (411U, Octets(port.subnet_mask)),
      (401U, Octets(port.gateway)),
      (412U, Unsigned(port.udp_port)),
      (402U, Boolean(false)),
    ] {
    device.define_property(network, property, [Application(value)])
  }
  device.define_property(network, 406U, [], array=true)
  device
}

///|
fn capability_bits(size : Int32, indexes : Array[Int32]) -> Value {
  let bytes = Array::make((size + 7) / 8, (0).to_byte())
  for index in indexes {
    let pos = index / 8
    bytes[pos] = (bytes[pos].to_int() | (128 >> (index % 8))).to_byte()
  }
  Bits((8 - size % 8) % 8, Bytes::from_array(bytes))
}

///|
fn Device::required_property_ids(
  self : Device,
  id : ObjectId,
) -> Array[UInt32] raise BacnetError {
  let base = [75U, 77U, 79U, 371U]
  let required = match id.kind {
    8 =>
      [
        112U, 121U, 120U, 70U, 44U, 12U, 98U, 139U, 97U, 96U, 76U, 62U, 107U, 11U,
        73U, 30U, 155U,
      ]
    56 =>
      [
        111U, 103U, 81U, 427U, 482U, 416U, 420U, 425U, 426U, 399U, 408U, 400U, 411U,
        401U, 412U, 402U, 406U,
      ]
    0 | 1 | 2 => [85U, 111U, 36U, 81U, 117U, 22U]
    3 | 4 => [85U, 111U, 36U, 81U, 84U]
    5 => [85U, 111U, 36U, 81U]
    13 | 14 | 19 => [85U, 111U, 36U, 81U, 74U]
    _ => []
  }
  base.append(required)
  if self.find(id).command is Some(_) {
    base.append([87U, 104U, 431U])
  }
  base
}

///|
/// Select the properties actually present, using standard required classifications.
fn Device::select_properties(
  self : Device,
  id : ObjectId,
  selector : UInt32,
) -> Array[UInt32] raise BacnetError {
  let all = self.all_property_ids(id)
  if selector == 8U {
    return all
  }
  let required = self.required_property_ids(id)
  all.filter(property => required.contains(property) == (selector == 105U))
}

///|
fn Device::read_reference(
  self : Device,
  reference : PropertyRef,
) -> PropertyRef {
  if reference.object.kind == 8 &&
    reference.object.instance == 4194303 &&
    reference.property == 75U {
    { ..reference, object: self.id, }
  } else {
    reference
  }
}

///|
fn matches_property_reference(
  expected : PropertyRef,
  actual : PropertyRef,
) -> Bool {
  expected == actual ||
  (
    expected.object.kind == 8 &&
    expected.object.instance == 4194303 &&
    expected.property == 75U &&
    actual.object.kind == 8 &&
    actual.object.instance != 4194303 &&
    actual.property == expected.property &&
    actual.index == expected.index
  )
}

///|
pub extend Ipv4PortConfig with @debug.Debug::{to_repr}
