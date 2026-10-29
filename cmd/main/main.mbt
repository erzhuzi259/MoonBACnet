///|
fn demo_device() -> @bac.Device raise {
  let d = @bac.Device::new(42, "moonbacnet-demo", 999U)
  d.add_point(
    @bac.ObjectId::new(0, 1),
    "temperature",
    Analog,
    Real(20.0F),
    units=62U,
  )
  d.add_point(
    @bac.ObjectId::new(2, 1),
    "setpoint",
    Analog,
    Real(19.0F),
    commandable=true,
    units=62U,
  )
  d.add_point(
    @bac.ObjectId::new(5, 1),
    "alarm",
    Binary,
    Enumerated(0U),
    commandable=true,
  )
  d
}

///|
async fn peer() -> Unit {
  let server = @bac.Server::new(demo_device())
  let line : Array[Byte] = []
  // This testing host uses a fixed logical clock. Real hosts supply monotonic seconds.
  while true {
    let chunk = match @stdio.stdin.read_some(max_len=4096) {
      Some(bytes) => bytes
      None => break
    }
    for byte in chunk {
      if byte == 10 {
        if !line.is_empty() && line[line.length() - 1] == 13 {
          line.pop() |> ignore
        }
        let text = @utf8.decode(Bytes::from_array(line)[:], ignore_bom=false)
        line.clear()
        let request = @bac.hex_decode(text)
        let response = server.datagram(request, "stdio-client", 0UL)
        let result = match response {
          Some(bytes) => @bac.hex_encode(bytes)
          None => "-"
        }
        @stdio.stdout.write(@utf8.encode(result + "\n"))
      } else {
        if line.length() >= 131070 {
          raise Failure("hex record byte budget")
        }
        line.push(byte)
      }
    }
  }
  if !line.is_empty() {
    raise Failure("truncated newline-delimited request")
  }
}

///|
fn canonical(mode : String, bytes : Bytes) -> Bytes raise {
  match mode {
    "tags" => @bac.encode_tags(@bac.decode_tags(bytes))
    "apdu" => @bac.encode_apdu(@bac.decode_apdu(bytes))
    "bvlc" => @bac.encode_bvlc(@bac.decode_bvlc(bytes))
    "npdu" => @bac.encode_npdu(@bac.decode_npdu(bytes))
    "rp" => @bac.encode_read_property(@bac.decode_read_property(bytes))
    "rp-ack" => @bac.encode_property_ack(@bac.decode_property_ack(bytes))
    "wp" => @bac.encode_write_property(@bac.decode_write_property(bytes))
    "rpm" => @bac.encode_read_multiple(@bac.decode_read_multiple(bytes))
    "rpm-ack" => @bac.encode_multiple_ack(@bac.decode_multiple_ack(bytes))
    "cov-sub" => @bac.encode_subscribe_cov(@bac.decode_subscribe_cov(bytes))
    "cov" => @bac.encode_cov(@bac.decode_cov(bytes))
    "whois" => @bac.encode_who_is(@bac.decode_who_is(bytes))
    "iam" => @bac.encode_i_am(@bac.decode_i_am(bytes))
    _ => raise Failure("unknown codec mode")
  }
}

///|
async fn run() -> Unit {
  let args = @env.args()
  if args.length() == 2 && args[1] == "peer" {
    peer()
    return
  }
  if args.length() != 4 {
    raise Failure("usage: moonbacnet MODE INPUT NEW_OUTPUT | peer")
  }
  if @fs.file_size(args[2][:]) > 65535L {
    raise Failure("input file exceeds byte budget")
  }
  let bytes = @fs.read_file(args[2][:]).binary()
  let result = canonical(args[1], bytes)
  @fs.write_file(args[3][:], result, create_mode=CreateNew)
}

///|
async fn main {
  run() catch {
    @bac.BacnetError::Invalid(message, offset) =>
      raise Failure("invalid BACnet at \{offset}: \{message}")
    @bac.BacnetError::Unsupported(message) =>
      raise Failure("unsupported BACnet profile: \{message}")
    @bac.BacnetError::Limit(message) =>
      raise Failure("BACnet resource limit: \{message}")
    @bac.BacnetError::State(message) =>
      raise Failure("BACnet state error: \{message}")
    @bac.BacnetError::Property(class, code) =>
      raise Failure("BACnet property error \{class}/\{code}")
    error => raise error
  }
}
