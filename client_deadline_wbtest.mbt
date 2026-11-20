///|
test "client deadline advances after retry and disappears on cancel" {
  let client = Client::new(timeout=3UL, retries=1)
  assert_eq(client.next_deadline(), None)
  let tx = client.start("peer", 12, b"", 10UL)
  assert_eq(client.next_deadline(), Some(13UL))
  ignore(client.poll(13UL))
  assert_eq(client.next_deadline(), Some(16UL))
  ignore(client.cancel("peer", tx.invoke))
  assert_eq(client.next_deadline(), None)
}
