#!/usr/bin/env ruby

require 'bundler/setup'
require 'dnsimple'

require 'timeout'
require 'net/http'
require 'uri'

$stdout.sync = $stderr.sync = true

USAGE = <<"EOF"
Usage: #{$0} <interface> <domain> <record>,
   interface = internet-facing local interface (e.g. "eth0"),
   domain    = DNSimple domain (e.g. "example.com"),
   record    = DNSimple record (e.g. "myip" = "myip.example.com"),

Don't forget to set one of the following environment variables:

  * "DOMAIN_TOKEN" (recommended, default) -- generated domain token,
    which must be specific to <domain> itself.
  * "OAUTH_V2_TOKEN" -- generated OAuth token, which must be
    specific to the account that owns <domain>.
EOF

def main(iface, domain, record)
  ddns = nil
  if token = ENV['DOMAIN_TOKEN']
    ddns = DDNS.new(domain_api_token: token)
  elsif token = ENV['OAUTH_V2_TOKEN']
    ddns = DDNS.new(access_token: token)
  else
    raise "Must set one of DOMAIN_TOKEN or OAUTH_V2_TOKEN in environment."
  end
  ipaddrs = ddns.get_addrs(iface)
  ddns.dns_set(record, domain, ipaddrs)
end

class DDNS
  def initialize(credentials)
    @client = Dnsimple::Client.new(credentials)
    @account_id = @client.identity.whoami.data.account.id
    @failsafe = false
  end

  def get_addrs_local(iface)
    addrs = []
    IO.popen(%w(/bin/ip -4 addr show dev) + [iface]) do |fh|
      fh.each_line do |line|
        if line =~ %r{^\s*inet ([0-9\.]+)/}
          addrs << $1
        end
      end
    end
    return addrs
  end

  def get_addr_remote
    Timeout.timeout(10) do
      ip = Net::HTTP.get(URI.parse('http://icanhazip.com/')).chomp
      quads = ip.split('.', 5)
      unless quads.count == 4 && quads.all? { |q| q =~ /\A\d+\z/ }
        result = if ip.length > 50 then ip[0,50] + "..." else ip end
        raise "Remote IP doesn't look like an IP: #{result.inspect}"
      end
      return ip
    end
  end

  def get_addrs(iface)
    addrs = Set.new
    begin
      addrs += get_addrs_local(iface)
    rescue StandardError => e
      puts "Failed to get local address(es): #{e.inspect}"
      @failsafe = true
    end
    begin
      addrs << get_addr_remote
    rescue StandardError => e
      puts "Failed to get remote address: #{e.inspect}"
      @failsafe = true
    end
    puts "Current IP addresses: #{addrs.to_a.inspect}"
    puts "FAILSAFE MODE ENABLED: At least one IP fetching approach failed." if @failsafe
    return addrs
  end

  def dns_get(name, domain)
    records = @client.zones.records(@account_id, domain, filter: {name: name}).data
    return records.map do |rec|
      [rec.content, rec.id]
    end.to_h
  end

  def dns_set(name, domain, ipaddrs)
    fqdn = [name, domain].join('.')

    to_delete = dns_get(name, domain)
    to_create = Set.new

    ipaddrs.each do |ip|
      if existing = to_delete.delete(ip)
        puts "Found existing record for #{ip.inspect}."
      else
        to_create << ip
      end
    end

    to_delete.each do |ip, rec_id|
      if @failsafe
        puts "FAILSAFE MODE: Refusing to delete record for #{ip.inspect}."
      else
        puts "Deleting record for #{ip.inspect}."
        @client.zones.delete_record(@account_id, domain, rec_id)
      end
    end

    to_create.each do |ip|
      puts "Creating record for #{ip.inspect}."
      @client.zones.create_record(@account_id, domain, name: name, type: "a", content: ip)
    end
  end
end

abort(USAGE) unless ARGV.count == 3
main(*ARGV)
