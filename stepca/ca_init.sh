#!/bin/bash
set -eo pipefail

####The following can be edited###############
export STEPCA_INIT_NAME=EriscoTestCertificate
export STEPCA_INIT_PROVISIONER_NAME=admin
export STEPCA_INIT_PASSWORD=1234567890
##############################################

export STEPPATH=$(step path)
export STEPCA_INIT_DNS_NAMES="localhost, $(hostname -f), $(hostname -I | awk '{print $1}')"

export CONFIGPATH="$STEPPATH/config/ca.json"
export PWDPATH="$STEPPATH/secrets/password"
export PKCS_URI="pkcs11:module-path=/usr/lib/softhsm/libsofthsm2.so;token=$STEPCA_INIT_NAME;id=1000;object=key?pin-value=$STEPCA_INIT_PASSWORD"

# List of env vars required for step ca init
declare -ra REQUIRED_INIT_VARS=(STEPCA_INIT_NAME STEPCA_INIT_DNS_NAMES)

# Ensure all env vars required to run step ca init are set.
function init_if_possible () {
    local missing_vars=0
    for var in "${REQUIRED_INIT_VARS[@]}"; do
        if [ -z "${!var}" ]; then
            missing_vars=1
        fi
    done
    if [ ${missing_vars} = 1 ]; then
        >&2 echo "there is no ca.json config file; please run step ca init, or provide config parameters via STEPCA_INIT_ vars"
    else
        step_ca_init "${@}"
    fi
}

function generate_password () {
    set +o pipefail
    < /dev/urandom tr -dc A-Za-z0-9 | head -c40
    echo
    set -o pipefail
}

# Initialize a CA if not already initialized
function step_ca_init () {
    STEPCA_INIT_PROVISIONER_NAME="${STEPCA_INIT_PROVISIONER_NAME:-admin}"
    STEPCA_INIT_ADMIN_SUBJECT="${STEPCA_INIT_ADMIN_SUBJECT:-step}"
    STEPCA_INIT_ADDRESS="${STEPCA_INIT_ADDRESS:-:9000}"

    local -a setup_args=(
        --name "${STEPCA_INIT_NAME}"
        --dns "${STEPCA_INIT_DNS_NAMES}"
        --provisioner "${STEPCA_INIT_PROVISIONER_NAME}"
        --password-file "${STEPPATH}/password"
        --provisioner-password-file "${STEPPATH}/provisioner_password"
        --address "${STEPCA_INIT_ADDRESS}"
    )
    
    if [ -n "${STEPCA_INIT_PASSWORD_FILE}" ]; then
        cat < "${STEPCA_INIT_PASSWORD_FILE}" > "${STEPPATH}/password"
        cat < "${STEPCA_INIT_PASSWORD_FILE}" > "${STEPPATH}/provisioner_password"
    elif [ -n "${STEPCA_INIT_PASSWORD}" ]; then
        echo "${STEPCA_INIT_PASSWORD}" > "${STEPPATH}/password"
        echo "${STEPCA_INIT_PASSWORD}" > "${STEPPATH}/provisioner_password"
    else
        generate_password > "${STEPPATH}/password"
        generate_password > "${STEPPATH}/provisioner_password"
    fi
    if [ "${STEPCA_INIT_SSH}" == "true" ]; then
        setup_args=("${setup_args[@]}" --ssh)
    fi
    if [ "${STEPCA_INIT_ACME}" == "true" ]; then
        setup_args=("${setup_args[@]}" --acme)
    fi
    if [ "${STEPCA_INIT_REMOTE_MANAGEMENT}" == "true" ]; then
        setup_args=("${setup_args[@]}" --remote-management
                       --admin-subject "${STEPCA_INIT_ADMIN_SUBJECT}"
        )
    fi
    step ca init "${setup_args[@]}"
   	echo ""
    if [ "${STEPCA_INIT_REMOTE_MANAGEMENT}" == "true" ]; then
        echo "👉 Your CA administrative username is: ${STEPCA_INIT_ADMIN_SUBJECT}"
    fi
    echo "👉 Your CA administrative password is: $(< $STEPPATH/provisioner_password )"
    echo "🤫 This will only be displayed once."
    shred -u $STEPPATH/provisioner_password
    mv $STEPPATH/password $PWDPATH   
}

if [ -f /usr/sbin/pcscd ]; then
    /usr/sbin/pcscd
fi

if [ ! -f "${STEPPATH}/config/ca.json" ]; then
    init_if_possible
fi

##### Check if the keys already exists #####
if sudo softhsm2-util --show-slots | grep "$STEPCA_INIT_NAME" 2> /dev/null; then
    echo "👆 Token for step CA already initialized. To delete use 'softhsm2-util --delete-token --token $STEPCA_INIT_NAME'"
else
    # Key does not exist, initialize the token
    sudo softhsm2-util --init-token --free --token "$STEPCA_INIT_NAME" --label "$STEPCA_INIT_NAME" --so-pin "$STEPCA_INIT_PASSWORD" --pin "$STEPCA_INIT_PASSWORD"
fi

if step kms key --kms "$PKCS_URI" "pkcs11:id=2000;object=root-ca" 2>/dev/null; then
    echo "👆 Root-ca key already exists. Skipping kms creation."
else
    # Key does not exist, create using kms
    step kms create --json --kms "$PKCS_URI" "pkcs11:id=2000;object=root-ca"
    # Create certificate
    step certificate create --force --profile root-ca --kms "$PKCS_URI" --key "pkcs11:id=2000;object=root-ca" "${STEPCA_INIT_NAME} Root CA" "$STEPPATH/certs/root_ca.crt"
fi

if step kms key --kms "$PKCS_URI" "pkcs11:id=3000;object=intermediate-ca" 2>/dev/null; then
    echo "👆 Intermediate key already exists. Skipping kms creation."
else
    # Key does not exist, create using kms
    step kms create --json --kms "$PKCS_URI" "pkcs11:id=3000;object=intermediate-ca"
    # Create certificate
    step certificate create --force --profile intermediate-ca --kms "$PKCS_URI" --ca $STEPPATH/certs/root_ca.crt --ca-key "pkcs11:id=2000;object=root-ca" --key "pkcs11:id=3000;object=intermediate-ca" "${STEPCA_INIT_NAME} Intermediate CA" "${STEPPATH}/certs/intermediate_ca.crt"
    # Change config to ensure using new certificates generated
    sed -i "s|\"key\": \"${STEPPATH}/secrets/intermediate_ca_key\",|\"key\": \"pkcs11:id=3000;object=intermediate-ca\",\n\t\"kms\": {\n\t\t\"type\": \"pkcs11\",\n\t\t\"uri\": \"pkcs11:module-path=/usr/lib/softhsm/libsofthsm2.so;token=$STEPCA_INIT_NAME;id=1000;object=mykey?pin-value=$STEPCA_INIT_PASSWORD\"\n\t},|" "${STEPPATH}/config/ca.json"
fi

# Start step ca
cp /ca.json $STEPPATH/config/ca.json

cp certs/* /usr/local/share/ca-certificates
update-ca-certificates 

export oidc_host=$(hostname -I | awk '{print $1}')
export oidc_port="8443"

# Function to check network connectivity
check_connectivity() {
    while ! nc -z "$oidc_host" "$oidc_port"; do
        echo "Waiting for access to oidc @ $oidc_host:$oidc_port"
        sleep 20
    done
    # Connection is established, add provisioner and start step-ca
    step ca provisioner add keycloak --listen-address localhost:7000 --type oidc --client-id producer --client-secret kbOFBXI9tANgKUq8vXHLhT6YhbivgXxn --configuration-endpoint "https://$oidc_host:$oidc_port/realms/FindME/.well-known/openid-configuration"
    pkill -SIGTERM -f '/usr/local/bin/step-ca'
    /usr/local/bin/step-ca --password-file $PWDPATH $CONFIGPATH

    # Give the bound file permission to change the oidc and restart the step ca server
    chmod +x /home/oidc.sh 
}

# Run the function in the background
check_connectivity &

/usr/local/bin/step-ca --password-file $PWDPATH $CONFIGPATH

exec "${@}"
