# AutomaticAcmeDNS
Automatically renew ACME issued SSL certs using DNS verification. 
This is primarily for my use case of having a number of HTTP/HTTPS services running on a server with IPv6 addressing only and an NGINX reverse proxy running elsewhere which listens on IPv4 only and proxies traffic over IPv6 to the downstream server. In this circumstance, as HTTP verification for ACME is not deterministic as to which HTTP host it will query, the IPv6 listening server can use HTTP verification flawlessly (since, even if letsencrypt verifies against the IPv4-based reverse proxy, the reverse proxy will proxy that request to the IPv6 server and therefore pass,) however, the IPv4 reverse proxy will struggle to get a certificate to validate as it is very likely that the IPv6 host will be asked to verify, have no data to return (as it doesn't know about certbot running on the reverse proxy,) and cause the ACME verification to fail. This tool alleviates this by using DNS verification on the IPv4 reverse proxy while allowing the IPv6 server to still use HTTP based verification.

## Setup 
This is a script for systems administrators by a system administrator, so it isnt your mom's iMessage, it requires decent knowledge of BIND9 and bash, and is made for use with the certbot tool on a linux system.

The script is fairly well commented, you should be able to infer what you need from it. The few things I'll define are:
### ACME Subdomain and _acme-challenge records
This is one subdomain (really a zone but I thought of that after writing most of this) where all your ACME DNS records will be hosted. Your DNS setup will look something like this (note that this is multiple DNS zones shown together):
```.zone
; Note: As an avid DNSSEC enthusiast, even I do not value my sanity enough to bother deploying it for this.
; It probably wouldn't be *too* bad to implement, but it is so unimportant that I don't really care.

; There's no rule that you have to name the ACME Subdomain with the same name as your server's hostname,
; but it does make it easier, and who knows, maybe one day you'll want to do this on multiple hosts?
; I mean, after 6 years I haven't, but maybe one day I will.
servername_acme.clickable.systems.  IN  NS  servername.clickable.systems.

; Create a CNAME record at _acme-challenge.${the-domain-you-want-certs-for} that certbot/letsencrypt will be using for
; verification and have that CNAME point to a subdomain under the ACME Subdomain you defined above. By convention, I
; use a different CNAME (as in, different subdomain under the ACME subdomain) for every domain I'm verifying. This is
; technically not required but you would otherwise potentially break some concurrency that I outline in the comments
; in the script. The server resolved by your-cool-website.stellasec.com. *should* be the same as the server resolved by
; servername.clickable.systems., the alternative option is to setup zone transfers to occur from the master DNS server
; (on the same server as your-cool-website.stellasec.com.) and have a slave server listening on another server (the server
; you set in the ACME Subdomain NS record) as well as making sure that you actually update the zone's serial number (this
; script omits that for simplicity.) This seems more complicated than it's worth to me, and running just an authoritative
; DNS server isn't a huge load, plus it only has to be active when you're actively running ACME verification, so you could
; even do some funky run-a-bind-server-in-docker and then have a post-hook called by certbot to turn it off afterwards.
; Lastly, this also could be dealt with by using BIND's built-in dynamic updates, however that has some implications
; that I don't really want to deal with and is vaguely more complicated. 
_acme-challenge.your-cool-website.stellasec.com.  IN  CNAME  your-cool-website.servername_acme.clickable.systems.
```
### Master zone file
This is the zone file configured on the server which will be requesting the ACME certificates. It is basically just a bare-bones SOA and NS declaration, then one `$INCLUDE` directive for each CNAME you have to validate. An example is provided below:
```.zone
; I *think* letsencrypt might be smart enough to always query the authoritative DNS server to avoid caching? Either way,
; the records here are small, so I don't anticipate there being a case where you somehow cause meaningful downstream load
; with this configuration
$TTL	30
@	IN	SOA	servername.clickable.systems. stella.clickable.systems. (
			20201114	; Serial
			604800		; Refresh
			 86400		; Retry
			2419200		; Expire
			604800 )	; Negative Cache TTL
; Obviously, change this to match the what's declared in the parent zone.
@	IN	NS	servername.clickable.systems.
; Repeat these as needed, by convention, I name the files the same as the CNAME that they point to, and this script has been
; updated to assume that. You do have the right to change that if you'd like, but that seems messier than it's worth.
; Make sure the files you $INCLUDE actually exist (generally in the same directory as this zone file, which is /var/cache/bind
; by default on most sane systems.)
$INCLUDE	db.acme.your-cool-website
$INCLUDE	db.acme.your-uncool-website
```
### Slave zone files
These are the files which are `$INCLUDE`'d in the Master zone file. These are overwritted by the script, so can just start off as being empty files (to avoid BIND erroring) and should not need further intervention.
