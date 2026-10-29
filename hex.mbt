pub fn hex_encode(bytes : Bytes) -> String {
  let digits = "0123456789abcdef"
  let builder = StringBuilder::new()
  for byte in bytes {
    let n = byte.to_int()
    builder.write_char(digits.unsafe_get(n >> 4).to_char())
    builder.write_char(digits.unsafe_get(n & 15).to_char())
  }
  builder.to_string()
}

fn hex_digit(c : Int) -> Int raise BacnetError {
  if c >= 48 && c <= 57 { c-48 }
  else if c >= 65 && c <= 70 { c-55 }
  else if c >= 97 && c <= 102 { c-87 }
  else { raise Invalid("non-hex character", 0) }
}

pub fn hex_decode(text : String, limits? : Limits = Limits::default()) -> Bytes raise BacnetError {
  limits.validate()
  if text.length()%2 != 0 { raise Invalid("odd hex length", text.length()) }
  if text.length()/2 > limits.max_bytes { raise Limit("hex decoded bytes") }
  let w = Writer::new(limits.max_bytes)
  for i = 0; i < text.length(); i = i + 2 {
    let hi = hex_digit(text.unsafe_get(i).to_int())
    let lo = hex_digit(text.unsafe_get(i+1).to_int())
    w.u8((hi << 4) | lo)
  }
  w.finish()
}
