# Measure both proxy groups. The dashboard's latency button uses a 5s timeout,
# which is shorter than these nodes need; the chain needs roughly double.
def ping_sb [] {
    let u = "http%3A%2F%2Fwww.gstatic.com%2Fgenerate_204"
    ^curl -s $"http://127.0.0.1:9090/group/auto/delay?timeout=15000&url=($u)" | ignore
    ^curl -s $"http://127.0.0.1:9090/group/vpn%20%E2%87%A2%20auto/delay?timeout=20000&url=($u)" | ignore
}
