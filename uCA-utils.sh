#!/bin/bash
# Bash makes echo's behavior the same on OS X and Linux, while sh differs
canonical_readlink () {
    # OS X doesn't ship with GNU readlink.
    cd $(dirname $1);
    __filename=$(basename $1);
    if [ -h "$__filename" ]; then
        canonical_readlink $(readlink $__filename$);
    else
        echo "$(pwd -P)";
    fi
}

function init_globals () {
    # Globals
    # Do we have CA_PASSPHRASE defined in the environment already?
    if [ -z "${CA_PASSPHRASE}" ]; then
	pp=$(openssl rand -hex 32)
    else 
	pp="${CA_PASSPHRASE}"
    fi
    ocf="${realdir}/openssl.cnf"
    cfg="-config ${ocf}"
    cakey="${realdir}/private/ca.key"
    cacert="${realdir}/certs/ca.crt"
}

function make_file_structure () {
    destroy_file_structure
    pushd ${realdir} >/dev/null
    mkdir certs crl csrs newcerts private
    chmod 0700 private
    touch index.txt crlnumber
    echo 1000 > serial
    popd >/dev/null
}

function destroy_file_structure () {
    pushd ${realdir} >/dev/null
    rm -rf certs crl crl.pem csrs newcerts private index.txt crlnumber \
	index.txt.attr index.txt.attr.old serial serial.old index.txt.old \
	2>/dev/null
    popd >/dev/null
}

function generate_CA () {
    touch ${cakey}
    chmod 0600 ${cakey}
    export PP=${pp}
    openssl genrsa -aes256 -out ${cakey} -passout env:PP 4096 
    unset PP
    chmod 0400 ${cakey}
    touch ${cacert}
    chmod 0644 ${cacert}
    export PP=${pp}
    openssl req ${cfg} -new -x509 -days 1825 -key ${cakey} -sha256 \
	-extensions v3_ca -out ${cacert} -passin env:PP -batch
    unset PP
    chmod 0444 ${cacert}
}

function make_cert () {
    local cn=$1
    create_key ${cn}
    create_csr ${cn}
    sign_csr ${cn}
}

function create_key () {
    local cn=$1
    local f="private/${cn}.key"
    touch ${f}
    chmod 0600 ${f}
    openssl genrsa -out ${f} 4096
    chmod 0400 ${f}
}

function create_csr () {
    local cn=$1
    subj=""
    san=""
    build_subj_and_san ${cn}
    csr="csrs/${cn}.csr"
    touch ${csr}
    chmod 0644 ${csr}
    export SAN=$"DNS:${san}"
    openssl req ${cfg} -new -key private/${cn}.key -out csrs/${cn}.csr \
     -batch -subj "${subj}" -passin pass: -batch
    unset SAN
    chmod 0444 ${csr}
}

function build_subj_and_san () {
    local CN=$1
    local C=$(read_config "countryName_default")
    local ST=$(read_config "stateOrProvinceName_default")
    local L=$(read_config "localityName_default")
    local O=$(read_config "0.organizationName_default")
    local OU=$(read_config "organizationalUnitName_default")
    subj="/C=${C}/ST=${ST}/L=${L}/O=${O}/OU=${OU}/CN=${CN}"
    san=$(echo $CN | sed -e 's/[[:digit:]]$//' )
}

function read_config () {
    local arg=$1
    if [ -z "${ocfcache}" ] ; then
	ocfcache=$(<${ocf})
    fi
    local item=$(echo "${ocfcache}" | grep "^$arg" ${ocf} | \
	cut -d '=' -f 2 | sed -e 's/^ *//' -e 's/ *$//')
    echo ${item}
}  

function sign_csr () {
    local cn=$1
    local ctype=$2
    local ct="srvr_cert"
    case $ctype in
	client )
	    ct="usr_cert"
	    ;;
	* )
	    ;;
    esac

    local cert="certs/${cn}.crt"
    touch ${cert}
    chmod 0644 ${cert}
    export PP=${pp}
    openssl ca ${cfg} -keyfile ${cakey} -cert ${cacert} -extensions ${ct} \
	-notext -md sha256 -in csrs/${cn}.csr -out certs/${cn}.crt \
	-key ${PP} -batch
    unset PP
    chmod 0444 ${cert}
}

