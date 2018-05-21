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
acme_home="/var/lib/acmesh/.acme.sh"

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

mkdir -p "$acme_home"
chown acmesh:acmesh "$acme_home"
chmod 0755 "$acme_home"

chown acmesh:acmesh "$acme_dir"

# cleanup (old version)
if [ -e "$BASEDIR"/.acme_tiny.py ]; then
    rm "$BASEDIR"/.acme_tiny.py
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

	if [ ! -f "$request" ]; then continue; fi

	if [ ! -L "$request" ]; then
		echo "Migrating csr for $name..."
		sudo -u acmesh -g acmesh $acme_bin -ak 4096 --signcsr --csr "$request" -w "/var/www/public"
		rm "$request" && ln -s "$acme_home/$name/$name.csr" "$request"
		chown acmesh:acmesh "$acme_home/$name/$name.csr"
		echo ""
	fi

	if [ ! -L "$conf" ]; then
		if [ -f "$conf" ]; then
			echo "Migrating config for $name..."
			mv $conf "$acme_home"/"$name"/"$name".csr.conf
			ln -s "$acme_home/$name/$name.csr.conf" "$conf"
			chown acmesh:acmesh "$acme_home/$name/$name.csr.conf"
			echo ""
		fi
	fi

	if [ ! -L "$private" ]; then
		if [ -f "$private" ]; then
			echo "Migrating keys for $name..."
			mv "$private" "$acme_home/$name/$name.key"
			ln -s "$acme_home/$name/$name.key" "$private"
			chown acmesh:acmesh "$acme_home/$name/$name.key"
			echo ""
		fi
	fi

	if [ ! -L "$signed" ]; then
		if [ -f "$signed" ]; then
			echo "Migrating cert for $name..."
			rm "$signed" && ln -s "$acme_home/$name/$name.cer" "$signed"
			chown acmesh:acmesh "$acme_home/$name/$name.cer"
			echo ""
		fi
	fi

	if [ ! -L "$bundle" ]; then
		if [ -f "$bundle" ]; then
			echo "Migrating fullchain for $bundle..."
			rm "$bundle" && ln -s "$acme_home/$name/fullchain.cer" "$bundle"
			chown acmesh:acmesh "$acme_home/$name/fullchain.cer"
			echo ""
		fi
	fi
done

## process certs
for domain in "${acme_home}"/*.*/; do
	name=$(basename $domain)

	if [ ! -d "$domain" ]; then continue; fi

	echo "[$name]"
	sudo -u acmesh -g acmesh $acme_bin --renew -d "$name"
	echo ""
done

echo "All done."
echo ""
echo "cert-strickerei is now DEPRECATED."
echo "Consider running 'acme.sh --renew-all' in the future!"
