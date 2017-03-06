#!/bin/sh

# working directory
BASEDIR="/etc/cert-strickerei"

# directories
config_dir="$BASEDIR"/conf
request_dir="$BASEDIR"/.reqs
public_dir="$BASEDIR"/certs
private_dir="$BASEDIR"/private
acme_dir="$BASEDIR"/acme-challenge

# vars
keysize=4096
account_key="$BASEDIR"/.account.key
letsenc_x1="$BASEDIR/.lets-encrypt-x1-cross-signed.pem"
letsenc_x3="$BASEDIR/.lets-encrypt-x3-cross-signed.pem"
acme_tiny="$BASEDIR"/.acme_tiny.py
acme_tiny_checksum="c53352240fa43b6b7b0e4a76c6a9cb7dcbf60e876aea5749799c78bca3fab84b90742401da72956097ec3b10e1cc5930d8a93bcbd9cdb81274f8de1203d9560b  $acme_tiny"

#-------------------------------------------------------------------------------
# DO NOT EDIT AFTER THIS COMMENT!
#-------------------------------------------------------------------------------

create_private_key() {
	local target="$1"
	openssl genrsa "$keysize" > "$target"
	chmod 400 "$target"
}

create_cert_request() {
	local target="$1" private="$2" config="$3"
	openssl req -new -sha256 -key "$private" -config "$config" -utf8 -out "$target"
}

create_signed_cert() {
	local target="$1" request="$2"
	crt=$(sudo -u nobody -g nobody python2 "$acme_tiny" --account-key "$account_key" --csr "$request" --acme-dir "$acme_dir")
	if [ "$?" -eq "0" ]; then
		echo "$crt" > "$target"
	fi
}

create_chain_bundle() {
	local target="$1" signed="$2"
	local issuer=`openssl x509 -issuer -noout -in "$signed"`

	if echo "$issuer" | grep -q X1 ; then intermediate="$letsenc_x1" ; fi
	if echo "$issuer" | grep -q X3 ; then intermediate="$letsenc_x3" ; fi
	if [ -f "$intermediate" ]; then
		cat "$signed" "$intermediate" > "$target"
	else
		echo "Unknown issuer: $issuer"
		cat "$signed" > "$target"
	fi
}

get_days() {
	local target="$1"
	local enddate=`openssl x509 -in "$signed" -enddate -noout | awk -F'=' '{ print $2 }'`
	local endtime=`date --date="$enddate" +%s`
	local starttime=`date +%s`
	local days=$(( ($endtime - $starttime)/(60*60*24) ))
	echo "$days"
}

usage() {
    echo "usage: cert-strickerei [[-v] | [-h]]"
}

while [ "$1" != "" ]; do
	case $1 in
		-v | --verbose ) verbose=1
				 ;;
		-h | --help )    usage
				 exit
				 ;;
		* )              usage
				 exit 1
	esac
	shift
done

if [ "$verbose" = "1" ]; then
	echo "-- Configuration ---"
	echo "keysize:        $keysize"
	echo "account key:    $account_key"
	echo ""
	echo "-- Directories -----"
	echo "cert requests:  $request_dir"
	echo "public certs:   $public_dir"
	echo "private certs:  $private_dir"
	echo "acme challenge: $acme_dir"
	echo "-------------------"
	echo ""
fi

# create missing dirs
for d in "$config_dir" "$request_dir" "$public_dir" "$private_dir" "$acme_dir"; do
	if [ ! -d "$d" ]; then mkdir "$d" ; fi
done

# set permissions
chown nobody:root "$acme_dir"

# check for openssl
command -v openssl > /dev/null 2>&1
if [ "$?" -ne 0 ] ; then
	echo "ERROR: openssl is not installed! Exiting."
	exit 1
fi

# check for and download acme_tiny
if [ ! -x "$acme_tiny" ]; then
	wget -O - https://raw.githubusercontent.com/diafygi/acme-tiny/master/acme_tiny.py > "$acme_tiny"
	chmod +x "$acme_tiny"
fi

# check if acme_tiny is the one we expect
echo "$acme_tiny_checksum" | sha512sum -c > /dev/null 2>&1
if [ "$?" -ne 0 ] ; then
	echo "WARNING: Your acme_tiny script does not match the known checksum! Exiting."
	exit 1
fi

# check for and download intermediate certs
for pem in "$letsenc_x1" "$letsenc_x3"; do
	if [ ! -e "$pem" ]; then
		filename=$(basename "$pem")
		wget -O- "https://letsencrypt.org/certs/${filename#.}" > "$pem"
	fi
done

# check for account
if [ ! -e "$account_key" ]; then
	echo "Account key not found, generating one."
	openssl genrsa 4096 > "$account_key"
	chmod 0400 "$account_key"
fi

if ! ls "$config_dir"/*.cnf > /dev/null 2>&1; then
	echo "No .cnf files in $config_dir/, nothing to do."
	exit 0
fi

# process certs
for cnf in "$config_dir"/*.cnf; do
	name=`basename "${cnf%.cnf}"`
	hook="$config_dir/$name.hook"
	private="$private_dir/$name.key"
	request="$request_dir/$name.csr"
	signed="$public_dir/$name.crt"
	bundle="$public_dir/$name.pem"
	changed=0

	echo "[$name]"

	# private key generation
	if [ ! -e "$private" ]; then
		echo "Creating private key in $private"
		create_private_key "$private"
	fi

	# cert request generation
	if [ ! -e "$request" ]; then
		echo "Creating cert request in $request"
		create_cert_request "$request" "$private" "$cnf"
	fi

	# request signed certificate
	if [ ! -e "$signed" ]; then
		echo "Request signed certificate in $signed"
		create_signed_cert "$signed" "$request"
	fi

	# check if cert is still valid
	days_left=$(( $(get_days "$signed")+0 ))
	if [ "$days_left" -gt 7 ]; then
		if [ "$verbose" = "1" ]; then
			echo "Certificate is still valid for $days_left days"
		fi
	else
		echo "Renewing certificate ($days_left days left)"
		create_signed_cert "$signed" "$request"
		changed=1
	fi

	# create chain bundle
	if [ ! -e "$bundle" -o "$signed" -nt "$bundle" ]; then
		echo "Creating trusted chain bundle in $bundle"
		create_chain_bundle "$bundle" "$signed"
		changed=1
	fi

	# create chain bundle
	if [ -x "$hook" -a "$changed" -eq 1 ]; then
		echo "Running update hook $hook"
		"$hook"
	fi

	echo -e "ok\n"
done
