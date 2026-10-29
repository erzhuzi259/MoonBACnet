fn text_bytes(text : String, maximum : Int) -> Bytes raise BacnetError {
  let mut size = 0
  let mut i = 0
  while i < text.length() {
    let c = text.unsafe_get(i).to_int()
    if c >= 0xd800 && c <= 0xdbff {
      if i+1 >= text.length() { raise Invalid("unpaired surrogate", i) }
      let next = text.unsafe_get(i+1).to_int()
      if next < 0xdc00 || next > 0xdfff { raise Invalid("unpaired surrogate", i) }
      size += 4
      i += 2
    } else {
      if c >= 0xdc00 && c <= 0xdfff { raise Invalid("unpaired surrogate", i) }
      size += if c < 128 { 1 } else if c < 2048 { 2 } else { 3 }
      i += 1
    }
    if size > maximum { raise Limit("text bytes") }
  }
  @utf8.encode(text)
}

fn application_body(value : Value, limits : Limits) -> (Int, Bytes) raise BacnetError {
  let w = Writer::new(limits.max_bytes)
  let kind = match value {
    Null => 0
    Boolean(_) => 1
    Unsigned(v) => { w.put(unsigned_bytes(v)); 2 }
    Signed(v) => { w.put(signed_bytes(v)); 3 }
    Real(v) => { w.uint(v.reinterpret_as_uint(), 4); 4 }
    DoubleValue(v) => {
      let bits = v.reinterpret_as_uint64()
      w.uint((bits >> 32).to_uint(), 4)
      w.uint(bits.to_uint(), 4)
      5
    }
    Octets(b) => { w.put(b); 6 }
    Text(s) => { w.u8(0); w.put(text_bytes(s, limits.max_bytes-1)); 7 }
    Bits(unused, b) => {
      if !bits_valid(unused, b) { raise Invalid("bit string padding", 0) }
      w.u8(unused); w.put(b); 8
    }
    Enumerated(v) => { w.put(unsigned_bytes(v)); 9 }
    DateValue(d) => {
      if !date_valid(d) { raise Invalid("date components", 0) }
      w.u8(d.year); w.u8(d.month); w.u8(d.day); w.u8(d.weekday); 10
    }
    TimeValue(t) => {
      if !time_valid(t) { raise Invalid("time components", 0) }
      w.u8(t.hour); w.u8(t.minute); w.u8(t.second); w.u8(t.hundredth); 11
    }
    Object(id) => { w.uint(id.number(), 4); 12 }
  }
  (kind, w.finish())
}

fn application_value(kind : Int, body : Bytes, limits : Limits) -> Value raise BacnetError {
  let r = Reader::new(body, limits)
  let value : Value = match kind {
    0 => { if body.length() != 0 { raise Invalid("null length", 0) }; Null }
    2 => Unsigned(read_unsigned(body))
    3 => Signed(read_signed(body))
    4 => { if body.length() != 4 { raise Invalid("real length", 0) }; Real(Float::reinterpret_from_uint(r.uint(4))) }
    5 => {
      if body.length() != 8 { raise Invalid("double length", 0) }
      let bits = (r.uint(4).to_uint64() << 32) | r.uint(4).to_uint64()
      DoubleValue(bits.reinterpret_as_double())
    }
    6 => Octets(body)
    7 => {
      if r.u8() != 0 { raise Unsupported("character encoding other than UTF-8") }
      let bytes = r.take(r.remaining())
      let text = try @utf8.decode(bytes[:], ignore_bom=false) catch {
        _ => raise Invalid("malformed UTF-8", 0)
      }
      Text(text)
    }
    8 => {
      let unused = r.u8()
      let bytes = r.take(r.remaining())
      if !bits_valid(unused, bytes) { raise Invalid("bit string padding", 0) }
      Bits(unused, bytes)
    }
    9 => Enumerated(read_unsigned(body))
    10 => {
      if body.length() != 4 { raise Invalid("date length", 0) }
      let d : Date = { year: r.u8(), month: r.u8(), day: r.u8(), weekday: r.u8() }
      if !date_valid(d) { raise Invalid("date components", 0) }
      DateValue(d)
    }
    11 => {
      if body.length() != 4 { raise Invalid("time length", 0) }
      let t : Time = { hour: r.u8(), minute: r.u8(), second: r.u8(), hundredth: r.u8() }
      if !time_valid(t) { raise Invalid("time components", 0) }
      TimeValue(t)
    }
    12 => {
      if body.length() != 4 { raise Invalid("object identifier length", 0) }
      Object(ObjectId::from_number(r.uint(4)))
    }
    _ => raise Unsupported("application tag")
  }
  value
}
