#!/bin/sh
#
# $Id$
#
# SER configuration script
#
# disclaimer: extremely simplistic and experimental
# useful only for people who know what they are doing
# and want to save some typing
#
# call it to generate a basic script -- you have to
# carry out any subsequent changes manually
#

# ------------------- Variables ------------------------

# prompted variables
# SER_DOMAIN -- name of served domain, e.g., foo.bar.com
# SER_GWIP -- IP address of PSTN gateway, e.g. 10.0.0.1

# parameters that are typically not changed
SER_SQL_URI="mysql://ser:heslo@localhost/ser"
# set LIB_PATH if all modules are installed in a single
# directory; otherwise, modules are sought in 'modules'
# subdirectories
#SER_LIB_PATH="/usr/local/lib/ser/modules"


# --------------------- functions ---------------------------
function go_to_pstn()
{
	if [ -n "$SER_GWIP" ] ; then 
		cat << EOGOTOPSTN
	# now check if it's about PSTN destinations through our gateway;
	# note that 8.... is exempted for numerical non-gw destinations
	if (uri=~"sip:\+?[0-79][0-9]*@.*") {
		route(3);
		break;
	}; 
EOGOTOPSTN
	fi
}


function addr2re()
{
	echo $1 |  sed -ne "s/\./\\\./gp"
}

function gw_check()
{
	if [ -n "$SER_GWIP" ] ; then 
		cat << EOGWTEST
		if (uri=~"sip:[+0-9]+@$SER_GWIP_RE") {
			# it is gateway -- proceed to ACLs
			route(3);
			break;
		};
EOGWTEST
	fi
}

function mine_check()
{
	printf "uri=~\"[@:](sip[\.)?$SER_DOMAIN_TEST_RE([;:].*)*\" $SER_GW_TEST_RE"
}

function gw_m_check()
{
	if [ -n "$SER_GWIP" ] ; then 
		cat << EOMCHECK
		if (search("^(Contact|m): .*$SER_GWIP_RE")) {
			log(1, "LOG: alert: protected contacts\n");
			sl_send_reply("476", "No Server Address in Contacts Allowed" );
			break;
		};
EOMCHECK
	fi
}

function help()
{
	cat << EOHELP
Numbering plan is as follows:
- numbers beginning with 8 are considered aliases
- numbers beginning with + are considered ENUM destinations
EOHELP
	if [ -n "$SER_GWIP" ] ; then
		cat << EOHELP2
- all other numbers are considered PSTN destinations
  ... to dial PSTN, a user must have 'int' privilege
EOHELP2
	else
		echo "- all other numbers are considered usernames"
	fi
}

function usage()
{
	echo "Usage: $0 <domain_name> [<ip_address_of_gateway>]" \
		'> <config_file>' > /dev/stderr
	exit 1
}

function load_mod()
{
	if [ -n "$SER_LIB_PATH" ] ; then
		echo "loadmodule \"$SER_LIB_PATH/$1.so\""
	else
		echo "loadmodule \"modules/$1/$1.so\""
	fi
}

# ----------------------- user-parameter check ---------------
# SER_DOMAIN -- name of served domain, e.g., foo.bar.com
# SER_GWIP -- IP address of PSTN gateway, e.g. 10.0.0.1

if [ $# -gt 0 ] ; then
	SER_DOMAIN="$1"
	shift
	if [ $# -gt 0 ] ; then
		SER_GWIP="$1"
		shift
	fi
	if [ $# -gt 0 ] ; then
		usage
	fi
else
	usage
fi

# ---------------------- initialization -------------------------

# autodetection parameters
SER_IP=`/sbin/ifconfig eth0 | 
	sed -ne 's/\( \)*\(inet addr:\)\([0-9\.]*\).*/\3/gp'`

# construction of regular expressions
SER_IP_RE=`addr2re $SER_IP`
SER_DOMAIN_RE=`addr2re $SER_DOMAIN`

# tests
# - is this for my domain
SER_DOMAIN_TEST_RE=`printf "($SER_DOMAIN_RE|$SER_IP_RE)"`
# - is this for my gateway ?
if [ -n "$SER_GWIP" ] ; then
	SER_GWIP_RE=`addr2re $SER_GWIP`
	SER_GW_TEST_RE=`printf "| uri=~\"@$SER_GWIP_RE([;:].*)*\""`
fi

SER_REGISTRAR="registrar@$SER_DOMAIN"

# ---------------------- verficiation --------------------------
set | grep ^SER_ > /dev/stderr
echo > /dev/stderr
echo "IS EVERYTHING OK ???? (press ^C to interrupt)" > /dev/stderr
read


# --------------------- dump it here -------------------------

cat << EOF

#
# \$Id$
#
# autogenerated SER configuration 
#
# user: `id`
# system: `uname -a`
# date: `date`
#

# ----------- global configuration parameters ------------------------

debug=3
fork=yes
port=5060
log_stderror=no
memlog=5

mhomed=yes

fifo="/tmp/ser_fifo"

alias=$SER_DOMAIN

# uncomment to override config values for test 
/* 
debug=3             # debug level (cmd line: -ddd)
fork=no
port=5068
log_stderror=yes	# (cmd line: -E)
fifo="/tmp/ser_fifox"
 */


check_via=no		# (cmd. line: -v)
dns=no              # (cmd. line: -r)
rev_dns=no          # (cmd. line: -R)
children=16
# if changing fifo mode to a more restrictive value, put
# decimal value in there, e.g. dec(rw|rw|rw)=dec(666)=438
#fifo_mode=438

# ------------------ module loading ----------------------------------

`load_mod tm`
`load_mod sl`
`load_mod acc`
`load_mod rr`
`load_mod maxfwd`
`load_mod mysql`
`load_mod usrloc`
`load_mod registrar`
`load_mod auth`
`load_mod auth_db`
`load_mod textops`
`load_mod uri`
`load_mod group`
`load_mod msilo`
`load_mod enum`



# ----------------- setting module-specific parameters ---------------

# all DB urls here
modparam("usrloc|acc|auth_db|group|msilo|uri", "db_url",
	"$SER_SQL_URI")

# -- usrloc params --
/* 0 -- don't use mysql, 1 -- write_through, 2 -- write_back */
modparam("usrloc", "db_mode",   2)
modparam("usrloc", "timer_interval", 10)

# -- auth params --

modparam("auth_db", "calculate_ha1", yes)
#modparam("auth_db", "user_column",   "user_id")
modparam("auth_db", "password_column",   "password")
modparam("auth", "nonce_expire",  300)

# -- rr params --
# add value to ;lr param to make some broken UAs happy
modparam("rr", "enable_full_lr", 1)

# -- acc params --
# that is the flag for which we will account -- don't forget to
modparam("acc", "db_flag", 1 )
modparam("acc", "db_missed_flag", 3 )

# -- tm params --
modparam("tm", "fr_timer", 20 )
modparam("tm", "fr_inv_timer", 90 )
modparam("tm", "wt_timer", 20 )

# -- msilo params
modparam("msilo", "registrar", "sip:$SER_REGISTRAR")

# -- enum params --
#
modparam("enum", "domain_suffix", "e164.arpa.")


# -------------------------  request routing logic -------------------

# main routing logic

route{

	/* ********* ROUTINE CHECKS  ********************************** */

	# filter too old messages
	if (!mf_process_maxfwd_header("10")) {
		log("LOG: Too many hops\n");
		sl_send_reply("483", "Alas Too Many Hops");
		break;
	};
	if (len_gt( max_len )) {
		sl_send_reply("513", "Message too large sorry");
		break;
	};


	# Make sure that requests don't advertise addresses
	# from private IP space (RFC1918) in Contact HF
	# (note: does not match with folded lines)
	if (search("^(Contact|m): .*@(192\.168\.|10\.|172\.16)")) {
		# allow RR-ed requests, as these may indicate that
		# a NAT-enabled proxy takes care of it; unless it is
		# a REGISTER
		if ((method=="REGISTER" || ! search("^Record-Route:")) 
					&& !( src_ip==192.168.0.0/16 ||
						src_ip==10.0.0.0/8 || src_ip==172.16.0.0/12 )) {
			log("LOG: Someone trying to register from private IP again\n");
			sl_send_reply("479", "We don't accept private IP contacts" );
			break;
		};
	};

	# anti-spam -- if somene claims to belong to our domain in From,
	# challenge him (skip REGISTERs -- we will challenge them later)
	if (search("(From|F):.*$SER_DOMAIN_TEST_RE")) {
		# invites forwarded to other domains, like FWD may cause subsequent 
		# request to come from there but have iptel in From -> verify
		# only INVITEs (ignore FIFO/UAC's requests, i.e. src_ip==myself)
		if (method=="INVITE" &  !(src_ip==$SER_IP)) {
			if  (!(proxy_authorize(	"$SER_DOMAIN" /* realm */,
					"subscriber" /* table name */ ))) {
				proxy_challenge("$SER_DOMAIN" /* realm */, "0" /* no-qop */);
				break;
			};
			# to maintain outside credibility of our proxy, we enforce
			# username in From to equal digest username; user with
			# "john.doe" id could advertise "bill.gates" in From otherwise;
			if (!check_from()) {
				log("LOG: From Cheating attempt in INVITE\n");
				sl_send_reply("403", "That is ugly -- use From=id next time (OB)");
				break;
			};
            		# we better don't consume credentials -- some requests may be
            		# spiraled through our server (sfo@iptel->7141@iptel) and the
            		# subsequent iteration may challenge too, for example because of
            		# iptel claim in From; UACs then give up because they
        		# already submitted credentials for the given realm
			#consume_credentials();
		}; # INVITEs claiming to come from our domain
	} else if (method=="INVITE" && !(uri=~"[@:\.]$SER_DOMAIN_TEST_RE([;:].*)*" 
			# ... and we serve our gateway too if present
			$SER_GW_TEST_RE )) {
		#the INVITE neither claims to come from our domain nor is it targeted to it
		# -> junk it
		sl_send_reply("403", "No relaying");
		break;
	};


	/* ********* RR ********************************** */
	# to be safe, record route everything; UAs may use different
	# transport protocols and need to have SER in path
	record_route();
	# if route forces us to forward to some explicit destination,
	# do so; check however first that a cheater didn't preload 
	# a gateway destination to bypass PSTN ACLs

	if (loose_route()) {
		`gw_check`
		# route HF determined next hop; forward there
		append_hf("P-hint: rr-enforced\r\n");
		t_relay();
		break;
	};


	/*  *********  check for requests targeted out of our domain... ******* */
	# sign of our domain: there is '@' (username) or  : (nothing) in 
	# front of our domain name	; ('.' is not there -- we handle all
	# xxx.iptel.org as outbound hosts);if none of these cases matches, 
	# proceed with processing of outbound requests in route[2]
	if (!(`mine_check`)) {
		route(2);
		break;
	};


	/* ************ requests for our domain ********** */


	/* now, the request is for sure for our domain */


	# registers always MUST be authenticated to
	# avoid stealing incoming calls	
	if (method=="REGISTER") {

		# Make sure that users don't register infinite loops
		# (note: does not match with folded lines)
		if (search("^(Contact|m): .*@$SER_DOMAIN_TEST_RE")) {
			log(1, "LOG: alert: someone trying to set aor==contact\n");
			sl_send_reply("476", "No Server Address in Contacts Allowed" );
			break;
		};
		`gw_m_check`

		if (!www_authorize(	"$SER_DOMAIN" /* realm */, 
			 				"subscriber" /* table name */ )) {
			# challenge if none or invalid credentials
 			www_challenge(	"$SER_DOMAIN" /* realm */, 
							"0" /* no qop -- some phones can't deal with it */);
			break;
		};

		# prohibit attempts to grab someone else's To address 
		# using  valid credentials; 

		if (!check_to()) {
			log("LOG: To Cheating attempt\n");
			sl_send_reply("403", "That is ugly -- use To=id in REGISTERs");
			break;
		};
		# it is an authenticated request, update Contact database now
		if (!save("location")) {
			sl_reply_error();
		};
		m_dump();
		break;
	};

	# some UACs might be fooled by Contacts our UACs generated to make MSN
	# happy (web-im, e.g.) -- tell it is unreachable
	if (uri=~"sip:daemon@" ) {
		sl_send_reply("410", "daemon is gone");
		break;
	};

	# is this an ENUM destination (leading +?)? give it a try, if the lookup
	# doesn't change URI, just continue
	if (uri=~"sip:\+[0-9]+@") {
		if (!enum_query("voice")) { # if parameter empty, it defaults to "e2u+sip"
			enum_query(""); # E2U+sip
		};
	} else {
		# aliases  (take precedences over PSTN number; provisioning interface
		# is set up to assign aliases beginning with 8)
		lookup("aliases");
	};


	# check again, if it is still for our domain after aliases are resolved
	if (!(`mine_check`)) {
		route(5);
		break;
	};

	`go_to_pstn`

	# native SIP destinations are handled using our USRLOC DB
	if (!lookup("location")) {
		# handle user which was not found ...
		route(4);
		break;
	};
	# check whether some inventive user has uploaded  gateway 
	# contacts to UsrLoc to bypass our authorization logic
	`gw_check`

	/* ... and also report on missed calls ... */
	setflag(3);

	# we now know we may, we know where, let it go out now!
	append_hf("P-hint: USRLOC\r\n");
	if (!t_relay()) {
		sl_reply_error();
		break;
	};
}
#------------------- OUTBOUND ----------------------------------------

# routing logic for outbound requests targeted out of our domain
# (keep in mind messages to our users can end up here too: for example,
#  an INVITE may be UsrLoc-ed, then the other party uses outbound
#  proxy with r-uri=the usr_loced addredd (typically IP))
route[2] {
	append_hf("P-hint: OUTBOUND\r\n");
	t_relay();
}

#------- ALIASED OUTBOUND --------------------------------------------

# routing logic for inbound requests aliased outbound; unlike
# with real outbound requests we do not force authentication
# as these calls are server by our server and we do not want
# to disqualify unauthenticated request originatiors from other
# domains
route[5] {
	append_hf("P-hint: ALIASED-OUTBOUND\r\n");
	t_relay();
}

#----------------- PSTN ----------------------------------------------

# logic for calls to the PSTN
route[3] {
	# turn accounting on
	setflag(1);

	/* require all who call PSTN to be members of the "int" group;
	   apply ACLs only to INVITEs -- we don't need to protect other requests, as they
	   don't imply charges; also it could cause troubles when a call comes in via PSTN
	   and goes to a party that can't authenticate (voicemail, other domain) -- BYEs would
	   fail then; exempt Cisco gateway from authentication by IP address -- it does not
	   support digest
	*/
	if (method=="INVITE" && (!src_ip==$SER_GWIP)) {
		if (!proxy_authorize(	"$SER_DOMAIN" /* realm */,
						"subscriber" /* table name */))  {
			proxy_challenge( "$SER_DOMAIN" /* realm */, "0" /* no qop */ );
			break;
		};
		# let's check from=id ... avoids accounting confusion
		if (method=="INVITE" & !check_from()) {
			log("LOG: From Cheating attempt\n");
			sl_send_reply("403", "That is ugly -- use From=id next time (gw)");
			break;
		};

		if(!is_user_in("credentials", "int")) {
			sl_send_reply("403", "NO PSTN Privileges...");
			break;
		};
		consume_credentials();

	}; # INVITE to authorized PSTN

	# if you have passed through all the checks, let your call go to GW!
	rewritehostport("$SER_GWIP:5060");

	# snom conditioner
	if (method=="INVITE" && search("User-Agent: snom")) {
		replace("100rel, ", "");
	};

	append_hf("P-hint: GATEWAY\r\n");
	# use UDP to guarantee well-known sender port (TCP ephemeral)
	t_relay_to_udp("$SER_GWIP", "5060");
}



/* *********** handling of unavailable user ******************* */

route[4] {
/**/
	# message store 
	if (method=="MESSAGE") {
		t_newtran();
		if (m_store("0")) {
			t_reply("202", "Accepted for Later Delivery");
		} else {
			t_reply("503", "Service Unavailable");
		};
		break;
	};
/**/
	# non-Voip -- just send "off-line"
	if (!(method=="INVITE" || method=="ACK" || method=="CANCEL")) {
		sl_send_reply("404", "Not Found");
		break;
	};
	# voicemail subscribers ...
	t_newtran();
	t_reply("404", "Not Found");
	# we account missed incoming calls; previous statteful processing
	# guarantees that retransmissions are not accounted
	if (method=="INVITE") {
		acc_db_request("404 missed call", "missed_calls");
	};
}

EOF

help > /dev/stderr
