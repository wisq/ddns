# ddns

Moderately simple (but more complete) Dynamic DNS script for DNSimple.

## Why?

The focus here is on comprehensively covering all possible means of retrieving the IP address, such that it can still produce reasonable results even when the network is not functioning 100% correctly.

Basically, I wanted something that was pretty much 100% guaranteed to give me **some** way to reach my home gateway, even if things are currently topsy-turvy.

### Why not `ddns.sh`?

Differences compared to the [official example solution](https://developer.dnsimple.com/ddns/), `ddns.sh`:

* Can handle multiple addresses
* Can function even if the remote IP reporting service is down / unreachable
* Doesn't require hardcoding any IDs (e.g. record, account)
* Doesn't show your DNSimple OAuth token in `ps` listings

## How?

When run, the script composes a list of local IP addresses, based on

* all IP addresses attached to the given interface,
  * potentially less correct, but always available
* a remote IP-reporting service (http://icanhazip.com/)
  * more correct, but more possibility of failure

It then updates DNSimple "A" records (only if needed) to this list of IP addresses.
