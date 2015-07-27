#!/usr/bin/env ruby
#
require "openssl"
include OpenSSL

# Grab the cert that's passed in via stdin
csr = OpenSSL::X509::Request.new $stdin.read

# Get a list of custom attributes
atts = csr.attributes()

# If there aren't any custom csr attributes, don't sign
if atts.empty?
  exit 1
end

key = nil

# Spin through attributes and find our custom attribute to check against
atts.each do |a|
  if (a.oid=="extReq")
    val = a.value.value.first.value.first.value
    if val[0].value == "1.3.6.1.4.1.34380.1.1.4"
      key = val[1].value
    end
  end
end

# If the key for the attribute matches, sign
# Otherwise, exit 1 and don't sign
if key == "[your key here]"
  print "Match\n"
  exit 0
else
  print "No match\n"
  exit 1
end
