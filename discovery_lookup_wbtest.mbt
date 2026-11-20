///|
test "freshness lookup leaves the discovery directory intact" {
  let directory = DiscoveryDirectory::new()
  let device = ObjectId::new(8, 7)
  ignore(
    directory.observe(
      "peer",
      { device, max_apdu: 50U, segmentation: 3U, vendor: 1U, },
      10UL,
    ),
  )
  assert_eq(
    directory.lookup(device, 19UL, max_age=Some(10UL)).unwrap().peer,
    "peer",
  )
  assert_true(directory.lookup(device, 20UL, max_age=Some(10UL)) is None)
  assert_eq(directory.lookup(device, 10UL).unwrap().last_seen, 10UL)
}
