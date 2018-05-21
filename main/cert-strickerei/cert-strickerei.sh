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
account_key="$BASEDIR"/.account.key
acme_bin="/usr/bin/acme.sh"
acme_home="/home/stw/.acme.sh"

#-------------------------------------------------------------------------------
# DO NOT EDIT AFTER THIS COMMENT!
#-------------------------------------------------------------------------------

usage() {
    echo "usage: cert-strickerei [-h]"
}

while [ "$1" != "" ]; do
	case $1 in
		-h | --help )    usage
				 exit
				 ;;
		* )              usage
				 exit 1
	esac
	shift
done

# cleanup (old version)
if [ -e "$BASEDIR"/.acme_tiny.py ]; then
    rm"$BASEDIR"/.acme_tiny.py "$BASEDIR/.lets-encrypt-x1-cross-signed.pem" "$BASEDIR/.lets-encrypt-x3-cross-signed.pem"
fi

# check for acme.sh
command -v acme.sh > /dev/null 2>&1
if [ "$?" -ne 0 ] ; then
	echo "ERROR: acme.sh is not installed! Exiting."
	exit 1
fi

# migrate old csrs
for request in "$request_dir"/*.csr; do
	name=`basename "${request%.csr}"`
	conf="$config_dir/$name.cnf"
	hook="$config_dir/$name.hook"
	private="$private_dir/$name.key"
	signed="$public_dir/$name.crt"
	bundle="$public_dir/$name.pem"

	if [ ! -d "$request" ]; then continue; fi

	if [ ! -L "$request" ]; then
		echo "Migrating csr for $name..."
		$acme_bin --signcsr --csr "$request" -w "$acme_dir"
		rm "$request" && ln -s "$acme_home"/"$name"/"$name".csr "$request"
		chown acmesh:acmesh "$acme_home"/"$name"/"$name".csr
		echo ""
	fi

	if [ ! -L "$conf" ]; then
		if [ -f "$conf" ]; then
			echo "Migrating config for $name..."
			mv "$conf" "$acme_home"/"$name"/"$name".csr.conf
			ln -s "$acme_home"/"$name"/"$name".csr.conf "$conf"
			chown acmesh:acmesh "$acme_home"/"$name"/"$name".csr
			echo ""
		fi
	fi

	if [ ! -L "$private" ]; then
		if [ -f "$private" ]; then
			echo "Migrating keys for $name..."
			mv "$private" "$acme_home"/"$name"/"$name".key
			ln -s "$acme_home"/"$name"/"$name".key "$private"
			chown acmesh:acmesh "$acme_home"/"$name"/"$name".key
			echo ""
		fi
	fi
done

## process certs
for domain in "${acme_home}"/*.*/; do
	name=$(basename $domain)

	if [ ! -d "$domain" ]; then continue; fi

	echo "[$name]"
	$acme_bin --renew -d "$name"
	echo -e "ok\n"
done

echo "All done."
echo ""
echo "Consider running `acme.sh --renew-all` in the future!"
