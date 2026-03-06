#!/bin/bash


#If you want your zone files for the ACME subdomain (see README) to be somewhere else, make sure
#you declare that here. This is the standard path for bind9, hence why it is the default.
export dir=/var/cache/bind/
#Set append to 1 by default, see the comments below for what this means. This should be changed 
#per-domain and NOT globally.
export append=1
#The default base name of the zone files. By default, this creates individual files for each domain 
#at ${dir}${basefilename}${zone}, but that's just a convention and not a requirement. Also by
#convention, this file should start with "db." and it probably makes sense that ${dir}${basefilename}
#is also where your master zone file (the one with all the $INCLUDE directives, see README) is stored.
export basefilename=db.acme

#You HAVE TO change these to fit your file paths and domains
case $CERTBOT_DOMAIN in
	#This is the domain you want to verify, you must add one entry PER DOMAIN
	#Even if multiple domains share one SSL cert.
	#The switch statement (standard bash syntax for a switch/case statement) should contain as many case
	#statements as there are domains that are being verified by this script.
	"example.clickable.systems")
		#This zone is the name/nickname of the domain. It can be anything, but it has to match the
		#subdomain that is configured as the CNAME to the alias which is located at
		#_acme-challenge.$DOMAIN (which would be _acme-challenge.example.clickable.systems in this example)
		#The difference between the Canonical Name (CNAME) and alias/label is clarified in
		#RFC2181 page 11 section 10.1.1.
		export zone=example
	;;
	"wildcard.clickable.systems"|"*wildcard.clickable.systems")
		export zone=wildcard
		#We set append here because we have two (2) acme-challenge records to verify at the same time,
		#one for the wildcard and one for the domain itself (as far as I know, the wildcard "always"
		#includes the base domain as well.) 
		append=2
	;;
	*)
	#if this is ever run, it means certbot tried to verify a domain that was not in this case statement.
	#It should fail out and certbot should not continue, but configuring this in the first place isn't so
	#hard, is it?
		echo $CERTBOT_DOMAIN not found
		exit 1
	;;
esac

#This is an optimization I made after a few years. I don't really see a reason to keep the zone name separate
#separate the file name. You're free to look back at older commits and undo this change if you'd like. Really,
#the only reason I even keep these separate is to avoid potentially messing up the master zone file with an
#off-by-one error with `tail -n` and to make this script technically safe to run concurrently (as in, multiple
#domain verifications at once,) though I still stagger them for safety and to not abuse the certbot API as much.
export file=${basefilename}.${zone}

#For completeness, some relatively simple logic could be added here to grep against ${dir}${basefilename} to ensure
#that the specific zone file has a $INCLUDE in the master zone file, and if not, either error or add it. I'm 
#opting to not do this because I don't feel like testing it, and I don't add new domains to this often enough to
#care. 

#You can set the append variable for any specific certificate if you have a certificate which needs multiple 
#domains verified. Set append to the total number of records that need to be active (ie, how many domains
#need to be verified for one cert.) It subtracts one so the last domain name in the list is deleted (and since
#the order *should* be deterministic, this should be stable.)
#Certbot's DNS authorization flow first calls the pre-hook for each domain to be verified (which sets the unique DNS
#record for each domain, even though they may share a common CNAME), then it validates all of them at once afterwards. 
#This is why this logic is required.
tail -n $((append - 1)) $dir$file > tee $dir$file
#This is how it updates the zone file, it appends to the file, which should be empty unless $append was set. 
echo "$zone     IN      TXT     $CERTBOT_VALIDATION" >> $dir$file
#Reload BIND9 to read the new config. This is preferable to reloading the entire service as 1. it
#communicates directly to the daemon, 2. can be run as a non-root user to increase security (assuming
#the user is in the bind group and has write access to the zone files which also have to be accessible to
#the bind user.
rndc reload
