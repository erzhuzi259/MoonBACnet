priv struct Reader {
  data : Bytes
  mut pos : Int
}

fn Reader::new(data : Bytes, limits : Limits) -> Reader raise BacnetError {
  limits.validate()
  if data.length() > limits.max_bytes { raise Limit("input bytes") }
  { data, pos: 0 }
}

fn Reader::remaining(self : Reader) -> Int { self.data.length() - self.pos }

fn Reader::u8(self : Reader) -> Int raise BacnetError {
  if self.remaining() == 0 { raise Invalid("truncated byte", self.pos) }
  let result = self.data[self.pos].to_int()
  self.pos += 1
  result
}

fn Reader::take(self : Reader, n : Int) -> Bytes raise BacnetError {
  if n < 0 || n > self.remaining() { raise Invalid("truncated payload", self.pos) }
  let result = self.data[self.pos:self.pos+n].to_owned()
  self.pos += n
  result
}

fn Reader::uint(self : Reader, n : Int) -> UInt raise BacnetError {
  if n < 0 || n > 4 { raise Invalid("integer width", self.pos) }
  let mut v = 0U
  for i = 0; i < n; i = i + 1 { v = (v << 8) | self.u8().reinterpret_as_uint() }
  v
}

fn Reader::done(self : Reader) -> Unit raise BacnetError {
  if self.remaining() != 0 { raise Invalid("trailing bytes", self.pos) }
}

priv struct Writer {
  bytes : Array[Byte]
  maximum : Int
}

fn Writer::new(maximum : Int) -> Writer { { bytes: [], maximum } }

fn Writer::u8(self : Writer, value : Int) -> Unit raise BacnetError {
  require_range(value, 0, 255, "octet")
  if self.bytes.length() >= self.maximum { raise Limit("output bytes") }
  self.bytes.push(value.to_byte())
}

fn Writer::uint(self : Writer, value : UInt, n : Int) -> Unit raise BacnetError {
  for i = n - 1; i >= 0; i = i - 1 {
    self.u8(((value >> (i*8)) & 255U).to_int())
  }
}

fn Writer::put(self : Writer, bytes : Bytes) -> Unit raise BacnetError {
  if bytes.length() > self.maximum - self.bytes.length() { raise Limit("output bytes") }
  for b in bytes { self.bytes.push(b) }
}

fn Writer::finish(self : Writer) -> Bytes { Bytes::from_array(self.bytes) }

fn unsigned_bytes(value : UInt) -> Bytes raise BacnetError {
  let n = if value <= 255U { 1 } else if value <= 65535U { 2 }
    else if value <= 16777215U { 3 } else { 4 }
  let w = Writer::new(4)
  w.uint(value, n)
  w.finish()
}

fn signed_bytes(value : Int) -> Bytes raise BacnetError {
  let n = if value >= -128 && value <= 127 { 1 }
    else if value >= -32768 && value <= 32767 { 2 }
    else if value >= -8388608 && value <= 8388607 { 3 } else { 4 }
  let w = Writer::new(4)
  w.uint(value.reinterpret_as_uint(), n)
  w.finish()
}

fn read_unsigned(data : Bytes) -> UInt raise BacnetError {
  if data.length() < 1 || data.length() > 4 { raise Invalid("unsigned width", 0) }
  Reader::new(data, Limits::default()).uint(data.length())
}

fn read_signed(data : Bytes) -> Int raise BacnetError {
  let value = read_unsigned(data)
  let shift = (4-data.length())*8
  (value << shift).reinterpret_as_int() >> shift
}
