#!/bin/bash
#===============================================================================
#
#          FILE: create_cert.sh
#
#         USAGE: ./create_cert.sh domain.com,domain.org
#
#   DESCRIPTION: Script to create a PKI infrastructure,
#                Request and sign certificates
#
#         NOTES: ---
#       CREATED: 20-03-20 13:28:50
#===============================================================================
set -e

# Adjust to your needs
Country='AU'
StateOrProvince='Some State'
Locality='Locality Name'
Organization='Organization Name'
EmailAddress='Email Address'
CACN="CA Common Name"

# Passwords
CAPass='secretpassword'
ServerPass='serverpassword'

# Arguments
Domains="$1"
DefaultDomain="${Domains%%,*}"
RealPath="$(dirname $(readlink -f $0))"

CreateConf() {
    local AltNames=""
    local Domain
    for Domain in $(tr ',' ' ' <<< "$Domains"); do
        AltNames+="DNS.$Counter = $Domain"$'\n'
        AltNames+="DNS.$(($Counter+1)) = *.$Domain"$'\n'
        AltNames+="DNS.$(($Counter+2)) = *.*.$Domain"$'\n'
        AltNames+="DNS.$(($Counter+3)) = *.*.*.$Domain"$'\n'
        AltNames+="DNS.$(($Counter+4)) = *.*.*.*.$Domain"$'\n'
        Counter+=5
    done
    Conf=$(cat << EOM
[ ca ]
default_ca = CA_default

[ CA_default ]
dir               = $RealPath
certs             = \$dir/certs
crl_dir           = \$dir/crl
new_certs_dir     = \$dir/newcerts
database          = \$dir/index.txt
serial            = \$dir/serial
RANDFILE          = \$dir/private/.rand
private_key       = \$dir/private/ca.key
certificate       = \$dir/certs/ca.crt
crlnumber         = \$dir/crlnumber
crl               = \$dir/crl/ca.crl
crl_extensions    = crl_ext
default_crl_days  = 30
default_md        = sha256
name_opt          = ca_default
cert_opt          = ca_default
default_days      = 375
preserve          = no
policy            = policy_strict

[ policy_strict ]
countryName             = match
stateOrProvinceName     = match
organizationName        = match
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[ crl_ext ]
authorityKeyIdentifier=keyid:always

[ req ]
default_bits        = 2048
req_extensions      = req_ext
distinguished_name  = dn
string_mask         = utf8only
default_md          = sha256
prompt              = no

[dn]
C=$Country
ST=$StateOrProvince
L=$Locality
O=$Organization
CN=$DefaultDomain
emailAddress=$EmailAddress

[ req_ext ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
$AltNames
EOM
)
}


CreateCA() {
    # CA key
    mkdir -p certs crl newcerts private csr
    chmod 700 private
    touch index.txt
    [[ -f serial ]] || echo 1000 > serial
    if [[ ! -e private/ca.key ]]; then
        openssl genrsa -aes256 -passout pass:"$CAPass" \
                       -out private/ca.key 4096
        chmod 400 private/ca.key
    fi

    # CA cert
    if [[ ! -e certs/ca.crt ]]; then
        openssl req -passin pass:"$CAPass" \
                    -key private/ca.key \
                    -new -x509 \
                    -days 7300 \
                    -sha256 \
                    -extensions v3_ca \
                    -out certs/ca.crt \
                    -subj "/C=$Country/ST=$StateOrProvince/L=$Locality/O=$Organization/CN=$CACN/emailAddress=$EmailAddress"
    fi
}


CreateKey() {
    openssl genrsa -aes256 -passout pass:"$ServerPass" \
                   -out private/${DefaultDomain}.key.secure 2048
    openssl rsa -in private/${DefaultDomain}.key.secure \
                -passin pass:"$ServerPass" \
                -out private/${DefaultDomain}.key
}



CreateCsr() {
    Counter=1
    openssl req -key private/${DefaultDomain}.key \
                -new -sha256 \
                -out csr/${DefaultDomain}.csr \
                -batch \
                -config <( echo "$Conf" )
}


SignCsr() {
    openssl ca -extensions req_ext \
               -days 375 \
               -notext \
               -md sha256 \
               -in csr/${DefaultDomain}.csr  \
               -out certs/${DefaultDomain}.crt \
               -passin pass:"$CAPass" \
               -batch \
               -config <( echo "$Conf" )

}


CopyToPub() {
    mkdir -p pub/${DefaultDomain}
    cp private/${DefaultDomain}.key pub/${DefaultDomain}
    cp certs/${DefaultDomain}.crt pub/${DefaultDomain}
}


### Main
if [[ -z $Domains ]]; then
    echo "No domains given."
    exit 1
fi

CreateConf
CreateCA
CreateKey
CreateCsr
SignCsr
CopyToPub

